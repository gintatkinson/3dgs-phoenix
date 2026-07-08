# Implementation Plan: Swap Epic 1 and Epic 2 for Windowing Lifecycle Alignment

This plan proposes renaming the local files, headers, and GitHub issues for Epic 1 and Epic 2 to satisfy the requirement that **Platform-Agnostic Scene-Based Lifecycle (Windowing)** is positioned as **Epic 1**.

## Proposed Changes

### 1. Rename Epic Specification Files
- **Rename** `docs/epics/epic-02-scene-lifecycle.md` to `docs/epics/epic-01-scene-lifecycle.md`.
  - Update YAML frontmatter: `title: "Epic 1: Platform-Agnostic Scene-Based Lifecycle (Windowing) Epic"`
  - Update header: `# Epic 1: Platform-Agnostic Scene-Based Lifecycle (Windowing) Epic`
- **Rename** `docs/epics/epic-01-3d-visualization.md` to `docs/epics/epic-02-3d-visualization.md`.
  - Update YAML frontmatter: `title: "Epic 2: 3D Visualization Epic"`
  - Update header: `# Epic 2: 3D Visualization Epic`

### 2. Update References in Backlog Files
Modify the parent Epic links in the following files to point to the renamed paths and titles:
- [feat-01-native-3d-network-visualization.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/features/feat-01-native-3d-network-visualization.md) (point to `epic-02-3d-visualization.md`)
- [feat-02-3d-terrain-elevation-and-node-altitude-modeling.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/features/feat-02-3d-terrain-elevation-and-node-altitude-modeling.md) (point to `epic-02-3d-visualization.md`)
- [feat-45-isolated-scene-boot.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/features/feat-45-isolated-scene-boot.md) (point to `epic-01-scene-lifecycle.md`)
- [us-45-1-boot-args.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/user-stories/us-45-1-boot-args.md) (point to `epic-01-scene-lifecycle.md`)
- [us-45-2-grpc-uds.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/user-stories/us-45-2-grpc-uds.md) (point to `epic-01-scene-lifecycle.md`)
- [us-45-3-mac-dock.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/user-stories/us-45-3-mac-dock.md) (point to `epic-01-scene-lifecycle.md`)

### 3. Update GitHub Issue Titles
Rename issue titles on the GitHub tracker to maintain parity:
- **Issue #243**: Change title from `"EPIC: 3D Visualization Epic"` to `"Epic 2: 3D Visualization Epic"`.
- **Issue #247**: Change title from `"Epic 2: Platform-Agnostic Scene-Based Lifecycle (Windowing) Epic"` to `"Epic 1: Platform-Agnostic Scene-Based Lifecycle (Windowing) Epic"`.

### 4. Run Backlog Reconciler & Verification
- Execute `python3 skills/spec-orchestrator/scripts/reconcile_backlog.py` to sync changed files to tracker.
- Execute `python3 skills/spec-orchestrator/scripts/verify_model_coverage.py` to confirm exit code 0.

## Verification Plan
- Verify that `git status` shows the renaming and references updated cleanly.
- Verify both issues on GitHub tracker show the updated titles.
- Verify `git diff origin/main` is empty and successfully pushed.
