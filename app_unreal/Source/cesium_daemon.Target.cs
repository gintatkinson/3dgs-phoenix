using UnrealBuildTool;
using System.Collections.Generic;

public class cesium_daemonTarget : TargetRules
{
    public cesium_daemonTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        bOverrideBuildEnvironment = true;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("cesium_daemon");
    }
}
