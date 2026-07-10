#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "OffscreenRenderer.generated.h"

class USceneCaptureComponent2D;
class UTextureRenderTarget2D;

UCLASS()
class UOffscreenRenderer : public UActorComponent
{
	GENERATED_BODY()

public:
	UOffscreenRenderer();

	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;
	void Initialize(UWorld* World);
	void Shutdown();

	int64 GetIosurfaceId() const { return IosurfaceId; }
	USceneCaptureComponent2D* GetSceneCapture() const { return SceneCapture; }

#if PLATFORM_MAC
	void ExportFrameToIosurface();
#endif

private:
	void OnFrameCaptured();

	UPROPERTY()
	USceneCaptureComponent2D* SceneCapture;

	UPROPERTY()
	UTextureRenderTarget2D* RenderTarget;

	FDelegateHandle OnCaptureDelegateHandle;
	int64 IosurfaceId;

#if PLATFORM_MAC
	void* IosurfaceRef = nullptr;
	void* CurrentPixelBuffer = nullptr;
	void* MetalDevice = nullptr;
	void* MetalCommandQueue = nullptr;
	void* MetalTextureCache = nullptr;
#endif
};
