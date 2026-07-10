#include "DaemonServer.h"
#include "DaemonGameMode.h"
#include "OffscreenRenderer.h"
#include "CesiumGeoreference.h"
#include "Components/SceneCaptureComponent2D.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/Pawn.h"
#include "Kismet/GameplayStatics.h"
#include "Dom/JsonObject.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonReader.h"
#include "Async/Async.h"
#include "Async/TaskGraphInterfaces.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/select.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

FDaemonServer::FDaemonServer(ADaemonGameMode* InGameMode, const FString& InSocketPath)
	: GameMode(InGameMode)
	, SocketPath(InSocketPath)
	, ListenSocket(-1)
	, ClientSocket(-1)
	, Thread(nullptr)
	, bStopping(false)
{
	Thread = FRunnableThread::Create(this, TEXT("DaemonServerThread"), 0, TPri_Normal);
}

FDaemonServer::~FDaemonServer()
{
	Shutdown();
}

bool FDaemonServer::Init()
{
	ListenSocket = socket(AF_UNIX, SOCK_STREAM, 0);
	if (ListenSocket < 0)
	{
		UE_LOG(LogTemp, Error, TEXT("DaemonServer: Failed to create socket: %s"), UTF8_TO_TCHAR(strerror(errno)));
		return false;
	}

	int32 Flags = fcntl(ListenSocket, F_GETFL, 0);
	fcntl(ListenSocket, F_SETFL, Flags | O_NONBLOCK);

	int32 OptVal = 1;
	setsockopt(ListenSocket, SOL_SOCKET, SO_REUSEADDR, &OptVal, sizeof(OptVal));

	unlink(TCHAR_TO_UTF8(*SocketPath));

	struct sockaddr_un Addr;
	memset(&Addr, 0, sizeof(Addr));
	Addr.sun_family = AF_UNIX;
	FCStringAnsi::Strcpy(Addr.sun_path, sizeof(Addr.sun_path), TCHAR_TO_UTF8(*SocketPath));

	if (bind(ListenSocket, (struct sockaddr*)&Addr, sizeof(Addr)) < 0)
	{
		UE_LOG(LogTemp, Error, TEXT("DaemonServer: Failed to bind to %s: %s"), *SocketPath, UTF8_TO_TCHAR(strerror(errno)));
		close(ListenSocket);
		ListenSocket = -1;
		return false;
	}

	if (listen(ListenSocket, 1) < 0)
	{
		UE_LOG(LogTemp, Error, TEXT("DaemonServer: Failed to listen: %s"), UTF8_TO_TCHAR(strerror(errno)));
		close(ListenSocket);
		ListenSocket = -1;
		return false;
	}

	UE_LOG(LogTemp, Log, TEXT("DaemonServer: Listening on %s"), *SocketPath);
	return true;
}

uint32 FDaemonServer::Run()
{
	while (!bStopping)
	{
		if (ClientSocket < 0)
		{
			fd_set ReadFds;
			FD_ZERO(&ReadFds);
			FD_SET(ListenSocket, &ReadFds);

			struct timeval Timeout;
			Timeout.tv_sec = 0;
			Timeout.tv_usec = 100000;

			int32 Ret = select(ListenSocket + 1, &ReadFds, nullptr, nullptr, &Timeout);
			if (Ret < 0)
			{
				if (errno == EINTR)
				{
					continue;
				}
				UE_LOG(LogTemp, Error, TEXT("DaemonServer: select error: %s"), UTF8_TO_TCHAR(strerror(errno)));
				break;
			}

			if (Ret > 0 && FD_ISSET(ListenSocket, &ReadFds))
			{
				ClientSocket = accept(ListenSocket, nullptr, nullptr);
				if (ClientSocket >= 0)
				{
					int32 ClientFlags = fcntl(ClientSocket, F_GETFL, 0);
					fcntl(ClientSocket, F_SETFL, ClientFlags | O_NONBLOCK);
					ClientBuffer.Empty();
					UE_LOG(LogTemp, Log, TEXT("DaemonServer: Client connected (fd=%d)"), ClientSocket);
				}
			}
		}
		else
		{
			fd_set ReadFds;
			FD_ZERO(&ReadFds);
			FD_SET(ClientSocket, &ReadFds);

			struct timeval Timeout;
			Timeout.tv_sec = 0;
			Timeout.tv_usec = 100000;

			int32 Ret = select(ClientSocket + 1, &ReadFds, nullptr, nullptr, &Timeout);
			if (Ret < 0)
			{
				if (errno == EINTR)
				{
					continue;
				}
				UE_LOG(LogTemp, Error, TEXT("DaemonServer: select error: %s"), UTF8_TO_TCHAR(strerror(errno)));
				close(ClientSocket);
				ClientSocket = -1;
				ClientBuffer.Empty();
				continue;
			}

			if (Ret > 0 && FD_ISSET(ClientSocket, &ReadFds))
			{
				char RecvBuf[4096];
				ssize_t BytesRead = recv(ClientSocket, RecvBuf, sizeof(RecvBuf) - 1, 0);

				if (BytesRead <= 0)
				{
					UE_LOG(LogTemp, Log, TEXT("DaemonServer: Client disconnected (fd=%d)"), ClientSocket);
					close(ClientSocket);
					ClientSocket = -1;
					ClientBuffer.Empty();
				}
				else
				{
					RecvBuf[BytesRead] = '\0';
					ClientBuffer += UTF8_TO_TCHAR(RecvBuf);

					int32 NewlineIdx;
					while ((NewlineIdx = ClientBuffer.Find(TEXT("\n"))) != INDEX_NONE)
					{
						FString Message = ClientBuffer.Left(NewlineIdx).TrimStartAndEnd();
						ClientBuffer.RightChopInline(NewlineIdx + 1);

						if (!Message.IsEmpty())
						{
							ProcessMessage(Message);
						}
					}

					if (ClientBuffer.Len() > 65536)
					{
						UE_LOG(LogTemp, Warning, TEXT("DaemonServer: Client buffer overflow, disconnecting (fd=%d)"), ClientSocket);
						close(ClientSocket);
						ClientSocket = -1;
						ClientBuffer.Empty();
					}
				}
			}

			FString Response;
			while (OutgoingQueue.Dequeue(Response) && ClientSocket >= 0)
			{
				FString Msg = Response + TEXT("\n");
				FTCHARToUTF8 Converter(*Msg);
				send(ClientSocket, Converter.Get(), Converter.Length(), 0);
			}
		}

		FPlatformProcess::Sleep(0.01f);
	}

	return 0;
}

void FDaemonServer::Stop()
{
	bStopping = true;
}

void FDaemonServer::Shutdown()
{
	if (bStopping)
	{
		return;
	}

	bStopping = true;

	if (ClientSocket >= 0)
	{
		close(ClientSocket);
		ClientSocket = -1;
	}

	if (ListenSocket >= 0)
	{
		close(ListenSocket);
		ListenSocket = -1;
	}

	unlink(TCHAR_TO_UTF8(*SocketPath));

	if (Thread)
	{
		Thread->WaitForCompletion();
		delete Thread;
		Thread = nullptr;
	}
}

void FDaemonServer::ProcessMessage(const FString& Message)
{
	TSharedPtr<FJsonObject> JsonObject;
	TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(Message);

	if (!FJsonSerializer::Deserialize(Reader, JsonObject) || !JsonObject.IsValid())
	{
		OutgoingQueue.Enqueue(TEXT("{\"type\":\"error\",\"message\":\"Invalid JSON\"}"));
		return;
	}

	FString Type;
	if (!JsonObject->TryGetStringField(TEXT("type"), Type))
	{
		OutgoingQueue.Enqueue(TEXT("{\"type\":\"error\",\"message\":\"Missing 'type' field\"}"));
		return;
	}

	if (Type == TEXT("update_camera"))
	{
		FString Response = HandleUpdateCamera(JsonObject);
		OutgoingQueue.Enqueue(Response);
	}
	else if (Type == TEXT("get_iosurface_id"))
	{
		FString Response = HandleGetIosurfaceId();
		OutgoingQueue.Enqueue(Response);
	}
	else if (Type == TEXT("health_check"))
	{
		FString Response = HandleHealthCheck();
		OutgoingQueue.Enqueue(Response);
	}
	else
	{
		FString ErrorResponse = FString::Printf(TEXT("{\"type\":\"error\",\"message\":\"Unknown type: %s\"}"), *Type);
		OutgoingQueue.Enqueue(ErrorResponse);
	}
}

FString FDaemonServer::HandleUpdateCamera(const TSharedPtr<FJsonObject>& Json)
{
	double Lat = 0.0, Lon = 0.0, Alt = 10000000.0;
	double Heading = 0.0, Pitch = -90.0, Roll = 0.0;

	Json->TryGetNumberField(TEXT("lat"), Lat);
	Json->TryGetNumberField(TEXT("lon"), Lon);
	Json->TryGetNumberField(TEXT("alt"), Alt);
	Json->TryGetNumberField(TEXT("heading"), Heading);
	Json->TryGetNumberField(TEXT("pitch"), Pitch);
	Json->TryGetNumberField(TEXT("roll"), Roll);

	UE_LOG(LogTemp, Log, TEXT("DaemonServer: Camera update - lat=%f lon=%f alt=%f heading=%f pitch=%f roll=%f"),
		Lat, Lon, Alt, Heading, Pitch, Roll);

	if (GameMode)
	{
		FGraphEventRef Task = FFunctionGraphTask::CreateAndDispatchWhenReady(
			[this, Lat, Lon, Alt, Heading, Pitch, Roll]()
			{
				ACesiumGeoreference* GeoRef = ACesiumGeoreference::GetDefaultGeoreference(GameMode);
				if (!GeoRef) return;

				FVector UePos = GeoRef->TransformLongitudeLatitudeHeightPositionToUnreal(
					FVector(Lon, Lat, Alt));

				if (GameMode && GameMode->OffscreenRenderer)
				{
					USceneCaptureComponent2D* Capture = GameMode->OffscreenRenderer->GetSceneCapture();
					if (Capture)
					{
						Capture->SetWorldLocation(UePos);
					}
				}

				UWorld* World = GameMode->GetWorld();
				if (!World) return;

				APlayerController* PC = World->GetFirstPlayerController();
				if (!PC) return;

				if (PC->GetPawn())
				{
					PC->GetPawn()->SetActorLocation(UePos);
				}
				PC->SetControlRotation(FRotator(Pitch, Heading, Roll));
			},
			TStatId(), nullptr, ENamedThreads::GameThread);

		FTaskGraphInterface::Get().WaitUntilTaskCompletes(Task);
	}

	return TEXT("{\"type\":\"camera_updated\",\"status\":\"ok\"}");
}

FString FDaemonServer::HandleGetIosurfaceId()
{
	int64 Id = 0;
	if (GameMode && GameMode->OffscreenRenderer)
	{
		Id = GameMode->OffscreenRenderer->GetIosurfaceId();
	}

	return FString::Printf(TEXT("{\"type\":\"iosurface_id\",\"id\":%lld}"), Id);
}

FString FDaemonServer::HandleHealthCheck()
{
	return TEXT("{\"type\":\"health\",\"status\":\"ok\"}");
}
