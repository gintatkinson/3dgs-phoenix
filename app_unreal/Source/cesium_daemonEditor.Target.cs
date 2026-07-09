using UnrealBuildTool;
using System.Collections.Generic;

public class cesium_daemonEditorTarget : TargetRules
{
    public cesium_daemonEditorTarget(TargetInfo Target) : base(Target)
    {
        Type = TargetType.Editor;
        bOverrideBuildEnvironment = true;
        DefaultBuildSettings = BuildSettingsVersion.V5;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.Add("cesium_daemon");
    }
}
