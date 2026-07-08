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
            "InputCore" 
        });

        PrivateDependencyModuleNames.AddRange(new string[] { });
    }
}
