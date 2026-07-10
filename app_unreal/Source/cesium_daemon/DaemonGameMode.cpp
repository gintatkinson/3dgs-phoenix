#include "DaemonGameMode.h"
#include "OffscreenRenderer.h"
#include "DaemonServer.h"
#include "CesiumGeoreference.h"
#include "Engine/World.h"
#include "GameFramework/PlayerController.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"

ADaemonGameMode::ADaemonGameMode()
{
	if (!FParse::Value(FCommandLine::Get(), TEXT("-SceneId="), SceneId))
	{
		SceneId = TEXT("default");
	}

	UE_LOG(LogTemp, Log, TEXT("DaemonGameMode: Parsed SceneId=%s"), *SceneId);
}

void ADaemonGameMode::BeginPlay()
{
	Super::BeginPlay();

	OffscreenRenderer = NewObject<UOffscreenRenderer>(this);
	OffscreenRenderer->Initialize(GetWorld());

	ACesiumGeoreference* GeoRef = ACesiumGeoreference::GetDefaultGeoreference(this);
	if (GeoRef)
	{
		FVector UePos = GeoRef->TransformLongitudeLatitudeHeightPositionToUnreal(FVector(0.0, 0.0, 10000000.0));
		APlayerController* PC = GetWorld()->GetFirstPlayerController();
		if (PC)
		{
			if (PC->GetPawn())
			{
				PC->GetPawn()->SetActorLocation(UePos);
			}
			if (OffscreenRenderer && OffscreenRenderer->GetSceneCapture())
			{
				OffscreenRenderer->GetSceneCapture()->SetWorldLocation(UePos);
			}
		}
	}

	FString SocketPath = FString::Printf(TEXT("/tmp/cesium_daemon_%s.sock"), *SceneId);
	Server = MakeUnique<FDaemonServer>(this, SocketPath);
}

void ADaemonGameMode::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (Server)
	{
		Server->Shutdown();
		Server.Reset();
	}

	if (OffscreenRenderer)
	{
		OffscreenRenderer->Shutdown();
		OffscreenRenderer = nullptr;
	}

	Super::EndPlay(EndPlayReason);
}
