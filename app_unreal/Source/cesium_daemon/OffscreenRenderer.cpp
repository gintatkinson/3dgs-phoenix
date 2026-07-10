#include "OffscreenRenderer.h"
#include "Components/SceneCaptureComponent2D.h"
#include "Engine/TextureRenderTarget2D.h"
#include "Engine/World.h"
#include "Engine/GameViewportClient.h"
#include "GameFramework/PlayerController.h"
#include "TextureResource.h"

#if PLATFORM_MAC
#define FVector Apple_FVector
#include <CoreVideo/CVPixelBuffer.h>
#include <CoreVideo/CVPixelBufferIOSurface.h>
#include <IOSurface/IOSurface.h>
#undef FVector
#endif

static constexpr int32 kRenderWidth = 1920;
static constexpr int32 kRenderHeight = 1080;

UOffscreenRenderer::UOffscreenRenderer()
	: SceneCapture(nullptr)
	, RenderTarget(nullptr)
	, IosurfaceId(0)
{
	PrimaryComponentTick.bCanEverTick = true;
}

void UOffscreenRenderer::Initialize(UWorld* World)
{
	if (!World)
	{
		return;
	}

	RenderTarget = NewObject<UTextureRenderTarget2D>(this);
	RenderTarget->InitAutoFormat(kRenderWidth, kRenderHeight);
	RenderTarget->UpdateResourceImmediate(true);

	APlayerController* PC = World->GetFirstPlayerController();
	if (!PC)
	{
		return;
	}

	SceneCapture = NewObject<USceneCaptureComponent2D>(PC);
	SceneCapture->RegisterComponentWithWorld(World);
	SceneCapture->AttachToComponent(PC->GetRootComponent(), FAttachmentTransformRules::SnapToTargetIncludingScale);
	SceneCapture->TextureTarget = RenderTarget;
	SceneCapture->CaptureSource = ESceneCaptureSource::SCS_FinalColorLDR;
	SceneCapture->bCaptureEveryFrame = true;
	SceneCapture->bCaptureOnMovement = false;

	IosurfaceId = 0;

#if PLATFORM_MAC
	{
		CFMutableDictionaryRef Props = CFDictionaryCreateMutable(
			kCFAllocatorDefault, 0,
			&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

		int32 Width = kRenderWidth;
		int32 Height = kRenderHeight;
		int32 PixelFormat = kCVPixelFormatType_32BGRA;
		int32 BytesPerElement = 4;

		CFNumberRef NumWidth = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &Width);
		CFNumberRef NumHeight = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &Height);
		CFNumberRef NumFormat = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &PixelFormat);
		CFNumberRef NumBPE = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &BytesPerElement);

		CFDictionarySetValue(Props, kIOSurfaceWidth, NumWidth);
		CFDictionarySetValue(Props, kIOSurfaceHeight, NumHeight);
		CFDictionarySetValue(Props, kIOSurfacePixelFormat, NumFormat);
		CFDictionarySetValue(Props, kIOSurfaceBytesPerElement, NumBPE);
		IOSurfaceRef Surface = IOSurfaceCreate(Props);

		CFRelease(NumWidth);
		CFRelease(NumHeight);
		CFRelease(NumFormat);
		CFRelease(NumBPE);
		CFRelease(Props);

		if (Surface)
		{
			IosurfaceRef = (void*)Surface;
			IosurfaceId = IOSurfaceGetID(Surface);

			CFMutableDictionaryRef PixBufAttrs = CFDictionaryCreateMutable(
				kCFAllocatorDefault, 0,
				&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			CFDictionarySetValue(PixBufAttrs, kCVPixelBufferMetalCompatibilityKey, kCFBooleanTrue);

			CVPixelBufferRef PixelBuf = nullptr;
			CVReturn CVResult = CVPixelBufferCreateWithIOSurface(
				kCFAllocatorDefault, Surface, PixBufAttrs, &PixelBuf);
			CFRelease(PixBufAttrs);

			if (CVResult == kCVReturnSuccess && PixelBuf)
			{
				CurrentPixelBuffer = (void*)PixelBuf;
			}
		}
	}
#endif
}

void UOffscreenRenderer::Shutdown()
{
#if PLATFORM_MAC
	if (CurrentPixelBuffer)
	{
		CVPixelBufferRelease((CVPixelBufferRef)CurrentPixelBuffer);
		CurrentPixelBuffer = nullptr;
	}
	if (IosurfaceRef)
	{
		CFRelease((IOSurfaceRef)IosurfaceRef);
		IosurfaceRef = nullptr;
	}
#endif

	if (SceneCapture)
	{
		SceneCapture->DestroyComponent();
		SceneCapture = nullptr;
	}
	RenderTarget = nullptr;
}

void UOffscreenRenderer::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
#if PLATFORM_MAC
	ExportFrameToIosurface();
#endif
}

#if PLATFORM_MAC
void UOffscreenRenderer::ExportFrameToIosurface()
{
	if (!RenderTarget || !IosurfaceRef)
	{
		return;
	}

	FTextureRenderTargetResource* RTResource = RenderTarget->GameThread_GetRenderTargetResource();
	if (!RTResource)
	{
		return;
	}

	TArray<FColor> Pixels;
	FReadSurfaceDataFlags ReadFlags(RCM_UNorm, CubeFace_MAX);
	ReadFlags.SetLinearToGamma(false);
	if (!RTResource->ReadPixels(Pixels, ReadFlags))
	{
		return;
	}

	IOSurfaceRef Surface = (IOSurfaceRef)IosurfaceRef;
	int32 SurfaceWidth = (int32)IOSurfaceGetWidth(Surface);
	int32 SurfaceHeight = (int32)IOSurfaceGetHeight(Surface);
	size_t SurfaceRowBytes = IOSurfaceGetBytesPerRow(Surface);

	IOSurfaceLock(Surface, 0, nullptr);
	uint8* BaseAddr = (uint8*)IOSurfaceGetBaseAddress(Surface);
	if (BaseAddr && Pixels.Num() >= SurfaceWidth * SurfaceHeight)
	{
		const uint8* SrcRow = (const uint8*)Pixels.GetData();
		for (int32 y = 0; y < SurfaceHeight; ++y)
		{
			FMemory::Memcpy(BaseAddr, SrcRow, SurfaceWidth * sizeof(FColor));
			BaseAddr += SurfaceRowBytes;
			SrcRow += SurfaceWidth * sizeof(FColor);
		}
	}
	IOSurfaceUnlock(Surface, 0, nullptr);
}
#endif
