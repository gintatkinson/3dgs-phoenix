using UnrealBuildTool;
using System.Collections.Generic;

public class cesium_daemonTarget : TargetRules
{
    public cesium_daemonTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V5;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("cesium_daemon");
    }
}
