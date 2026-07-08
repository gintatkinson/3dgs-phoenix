# Implementation Plan: Feature 46 (Headless Unreal Daemon Orchestration)

This feature provides the host process orchestration layer for spawning, monitoring, and restarting the offscreen Unreal Engine rendering daemon using the `-RenderOffscreen` flag.

## Proposed Changes

### Component: Unreal Daemon Management

#### [NEW] [unreal_daemon_manager.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/unreal_daemon_manager.dart)
- Create `UnrealDaemonManager` class to orchestrate spawning and auto-recovery.
- Create `ProcessWatcher` class to observe daemon exit codes.
- Implement logical exception classes: `DaemonBootFailure` and `MaxRebootThresholdReached`.
- Launch daemon with `-RenderOffscreen` argument.
- Track crash history within a 60-second window and throw `MaxRebootThresholdReached` if crashes exceed the threshold.

---

### Component: Verification & Test Suite

#### [NEW] [unreal_daemon_manager_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/unreal_daemon_manager_test.dart)
- Add mock tests verifying:
  - Process is spawned with `-RenderOffscreen`.
  - Recovery triggers restart on segmentation fault (exit code 139).
  - Restart loop is halted and throws `MaxRebootThresholdReached` on persistent crashes.

---

## Verification Plan

### Automated Tests
- Run the newly created test suite:
  ```bash
  flutter test test/cesium_3d/unreal_daemon_manager_test.dart
  ```
- Run the model coverage validation check to verify UML parity:
  ```bash
  python3 skills/spec-orchestrator/scripts/verify_model_coverage.py --spec-only
  ```
