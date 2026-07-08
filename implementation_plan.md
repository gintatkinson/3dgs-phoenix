# Implementation Plan: Add Coordinator Class to Feature Diagrams

This plan documents the changes required to add the `Coordinator` class definition with the `<<actor>>` stereotype to the Mermaid class diagrams in three feature specification files.

## Proposed Changes

### 1. Update `docs/features/feat-45-isolated-scene-boot.md`
- Locate the `classDiagram` block (lines 20-39).
- Insert the `Coordinator` class definition inside the diagram block:
  ```
      class Coordinator {
          <<actor>>
      }
  ```

### 2. Update `docs/features/feat-46-headless-orchestration.md`
- Locate the `classDiagram` block (lines 20-31).
- Insert the `Coordinator` class definition inside the diagram block:
  ```
      class Coordinator {
          <<actor>>
      }
  ```

### 3. Update `docs/features/feat-50-wasm-extensibility.md`
- Locate the `classDiagram` block (lines 20-39).
- Insert the `Coordinator` class definition inside the diagram block:
  ```
      class Coordinator {
          <<actor>>
      }
  ```

## Verification Plan
- Compile and verify that the Mermaid diagrams are syntax-correct.
- Run `python3 skills/spec-orchestrator/scripts/verify_model_coverage.py` to confirm the model coverage tool exits successfully.
- Ensure that `git diff origin/main` contains only the approved changes (plus any pre-existing changes) and that everything is pushed to the remote repository.
