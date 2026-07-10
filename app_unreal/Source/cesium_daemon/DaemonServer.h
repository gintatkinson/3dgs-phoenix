#pragma once

#include "CoreMinimal.h"
#include "HAL/Runnable.h"
#include "Containers/Queue.h"

class ADaemonGameMode;

class FDaemonServer : public FRunnable
{
public:
	FDaemonServer(ADaemonGameMode* InGameMode, const FString& InSocketPath);
	virtual ~FDaemonServer();

	virtual bool Init() override;
	virtual uint32 Run() override;
	virtual void Stop() override;

	void Shutdown();

private:
	void ProcessMessage(const FString& Message);
	FString HandleUpdateCamera(const TSharedPtr<FJsonObject>& Json);
	FString HandleGetIosurfaceId();
	FString HandleHealthCheck();

	ADaemonGameMode* GameMode;
	FString SocketPath;
	int32 ListenSocket;
	int32 ClientSocket;
	FRunnableThread* Thread;
	FThreadSafeBool bStopping;
	TQueue<FString> OutgoingQueue;
	FString ClientBuffer;
};
