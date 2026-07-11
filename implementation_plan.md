# Pipeline Execution Plan: Clean-Slate Specification & Implementation

This document defines the step-by-step pipeline execution plan to reset the workspace and rebuild the features, issues, code changes, and test suites from the beginning using the official pipeline scripts.

---

## Proposed Changes

### Step 1: Clean Workspace Reset
We will discard all local uncommitted modifications and untracked files to start from the baseline remote branch:
*   Run `git reset --hard origin/feat/251-cesium-native-clean`
*   Run `git clean -fd`

### Step 2: Pipeline 1 — Specification Generation & Reconciliation
We will re-run the specification engineering pipeline to decompose the backlog and register the features on GitHub:
1.  **Decompose the Epic:** Use the `spec-orchestrator` subagent to generate the 5 granular feature specification files:
    *   `docs/features/feat-19-gpu-texture-atlas.md`
    *   `docs/features/feat-20-geodetic-icosphere-generator.md`
    *   `docs/features/feat-21-binary-gltf-parser.md`
    *   `docs/features/feat-22-sse-lod-culling-engine.md`
    *   `docs/features/feat-23-thread-safe-ffi-bridge.md`
    *   *Checklists:* Update checklists in `docs/epics/epic-01-3d-visualization.md` and `docs/epics/epic-03-gpu-bridge.md` to reference the new features.
2.  **Backlog Reconciliation:** Execute the Python reconciliation tool:
    ```bash
    python3 .agents/skills/spec-orchestrator/scripts/reconcile_backlog.py
    ```
    This will create the 5 actual issue cards on the GitHub repository and write the generated issue numbers directly back into the YAML frontmatter of each feature file.
3.  **Model Coverage Check:** Run:
    ```bash
    python3 .agents/skills/spec-orchestrator/scripts/verify_model_coverage.py
    ```
    Confirm 100% specification and model coverage (exit code 0).

### Step 3: Pipeline 2 — TDD Implementation & Zero-Mocking Verification
We will re-implement the functional changes and zero-mocking test suites using isolated subagents:
1.  **Graphics Implementation:** Spawn the `Graphics Implementation Specialist` to write the codebase changes:
    *   *Correction A (Floating Nodes):* Seat nodes directly on the displaced terrain surface using geodetic normals.
    *   *Correction B (Drop Lines):* Render vertical ground-anchoring drop lines from node positions to the terrain surface.
    *   *Correction C (Link Occlusion):* Cull link lines that penetrate the Earth's curvature.
    *   *Correction D (Label overlaps):* Shift overlapping labels vertically in screen space.
    *   *Tile Normalization:* Scale GLB coordinates and displace high-resolution tile geometries.
2.  **Source Code Documentation:** Write full Doxygen (C++) and Dart Doc (Dart) comment blocks for all new and modified functions.
3.  **Zero-Mocking Test Suite:** Spawn the `Test Suite Engineer` to write the test files:
    *   Use `testWidgets` with real engine bindings.
    *   Decode real `ui.Image` references from raw bytes using the `createTestImage` utility.
    *   Load the actual compiled native FFI library from the `build/` directory.
    *   Add negative assertions verifying `FormatException` on corrupt GLB headers, `TileTimeoutException` on network timeouts, and FFI error events correctly propagate to the engine state.
    *   Mitigate `FakeAsync` hangs by wrapping all async calls in `tester.runAsync`.

### Step 4: Independent Verification & Audit
1.  **Safety Auditor:** Spawn the `Safety Auditor` subagent to audit all changes, run static analysis (`flutter analyze`), and verify that all 262 tests pass cleanly.
2.  **Commit and Push:** Stage, commit, and push all changes. Verify that `git diff origin/feat/251-cesium-native-clean` is completely empty.

---

## Verification Plan

### Automated Verification
*   Run `flutter analyze` across all target directories to verify no warnings are introduced.
*   Run `flutter test` to ensure that the complete unit and integration test suite remains 100% green.

### Walkthrough & Review
*   Generate the 5 individual solution walkthroughs matching the new issue IDs.
*   Present the walkthroughs and final diffs to you for review and sign-off.
