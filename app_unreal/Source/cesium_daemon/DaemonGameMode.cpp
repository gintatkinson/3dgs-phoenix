#include "DaemonGameMode.h"
#include "OffscreenRenderer.h"
#include "DaemonServer.h"
#include "CesiumGeoreference.h"
#include "Cesium3DTileset.h"
#include "CesiumIonServer.h"
#include "CesiumSunSky.h"
#include "Components/SceneCaptureComponent2D.h"
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

	UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: BeginPlay START, SceneId=%s"), *SceneId);

	ACesiumGeoreference* GeoRef = GetWorld()->SpawnActor<ACesiumGeoreference>();
	if (GeoRef)
	{
		UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: Georeference spawned, setting origin"));
		GeoRef->SetOriginLatitude(0.0);
		GeoRef->SetOriginLongitude(0.0);
		GeoRef->SetOriginHeight(0.0);
		UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: Georeference configured at origin"));
	}
	else
	{
		UE_LOG(LogTemp, Error, TEXT("DaemonGameMode: FAILED to spawn Georeference"));
	}

	ACesium3DTileset* Tileset = GetWorld()->SpawnActor<ACesium3DTileset>(
		ACesium3DTileset::StaticClass(), FTransform::Identity);
	if (Tileset)
	{
		UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: Tileset spawned, configuring..."));
		Tileset->SetGeoreference(GeoRef);
		Tileset->SetTilesetSource(ETilesetSource::FromCesiumIon);
		Tileset->SetIonAssetID(1);
		{
			UCesiumIonServer* IonServer = UCesiumIonServer::GetDefaultServer();
			if (IonServer)
			{
				Tileset->SetCesiumIonServer(IonServer);
				UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: Ion server configured: %s"), *IonServer->GetName());
			}
			else
			{
				UE_LOG(LogTemp, Warning, TEXT("DaemonGameMode: No default Ion server found!"));
			}
		}
		Tileset->RefreshTileset();
		UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: Tileset configured: Source=%d"),
			(int32)Tileset->GetTilesetSource());
	}
	else
	{
		UE_LOG(LogTemp, Error, TEXT("DaemonGameMode: FAILED to spawn Tileset"));
	}

	GetWorld()->SpawnActor<ACesiumSunSky>();
	UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: SunSky spawned"));

	FVector UePos = GeoRef->TransformLongitudeLatitudeHeightPositionToUnreal(FVector(0.0, 0.0, 10000000.0));
	UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: Camera target position = %s"), *UePos.ToString());

	APlayerController* PC = GetWorld()->GetFirstPlayerController();
	if (PC && UePos.SizeSquared() > 0.0f)
	{
		if (PC->GetPawn())
		{
			PC->GetPawn()->SetActorLocation(UePos);
			UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: Pawn moved to camera position"));
		}
	}

	GetWorld()->Tick(ELevelTick::LEVELTICK_All, 0.016f);
	UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: World ticked"));

	OffscreenRenderer = NewObject<UOffscreenRenderer>(this);
	OffscreenRenderer->Initialize(GetWorld());
	UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: OffscreenRenderer initialized"));

	if (OffscreenRenderer && OffscreenRenderer->GetSceneCapture())
	{
		OffscreenRenderer->GetSceneCapture()->SetWorldLocation(UePos);
		OffscreenRenderer->GetSceneCapture()->SetWorldRotation(FRotator(-90.0, 0.0, 0.0));
		UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: SceneCapture positioned"));
	}

	FString SocketPath = FString::Printf(TEXT("/tmp/cesium_daemon_%s.sock"), *SceneId);
	Server = MakeUnique<FDaemonServer>(this, SocketPath);
	UE_LOG(LogTemp, Display, TEXT("DaemonGameMode: BeginPlay DONE, socket=%s"), *SocketPath);
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
