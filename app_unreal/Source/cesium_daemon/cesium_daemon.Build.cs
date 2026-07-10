using UnrealBuildTool;

public class cesium_daemon : ModuleRules
{
    public cesium_daemon(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(new string[] { 
            "Core", 
            "CoreUObject", 
            "Engine", 
            "InputCore",
            "CesiumRuntime",
            "RHI",
            "RenderCore",
            "Renderer",
            "Sockets",
            "Networking",
            "Json",
            "JsonUtilities"
        });

        PrivateDependencyModuleNames.AddRange(new string[] { });

        if (Target.Platform == UnrealTargetPlatform.Mac)
        {
            PublicFrameworks.AddRange(new string[] { "CoreVideo", "IOSurface", "Metal" });
        }
    }
}
