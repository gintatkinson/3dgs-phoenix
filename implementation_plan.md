# Implementation Plan - Epic 4: WebAssembly Component Model Extensibility Spec Alignment

## 1. Objectives
- Restructure the headers of the Epic specification file `/Users/perkunas/jail/3dgs-phoenix/docs/epics/epic-04-wasm-extensibility.md` to match the required layout.
- Describe the component and interface methods under "Subsystem Component Definition" in normal markdown list format instead of `classDiagram`.
- Update the UML Class Diagram under "System-Level UML Class Diagram" to resolve invalid types, add multiplicities to all attributes/methods, and connect `PluginManager` to `PluginInstance`.
- Move the state machine diagram to "System State Machine Diagram".
- Add placeholders for "Operational Considerations" and "Security & Governance".

## 2. File Modifications

### `docs/epics/epic-04-wasm-extensibility.md`
- Restructure headers:
  - `## 1. Context`
  - `## 2. Requirements & Checklist` (Move Use Case UC-2 and User Stories here)
  - `## 3. Architecture` (Move subsystem component definition and system interaction sequence diagram here)
  - `## 4. Operational Considerations` (Add brief placeholder explaining plugin initialization, instance lifecycle, and host resource protection)
  - `## 5. Security & Governance` (Add brief placeholder explaining WASI filesystem sandbox, denied capabilities, and memory boundaries)
  - `## 6. Source References`
  - `## System-Level UML Class Diagram` (Place main class diagram here)
  - `## System State Machine Diagram` (Place state machine diagram here, moving it from section 4)
- Remove `classDiagram` code block under `### Subsystem Component Definition` and replace with normal markdown list.
- Modify the Class Diagram:
  - Add `PluginInstance` class.
  - Connect `PluginManager` to `PluginInstance` via `PluginManager o-- "0..*" PluginInstance : manages`.
  - Fix invalid types to primitives or defined classes.
  - Add multiplicities `[1]`, `[0..1]`, or `[0..*]` to all attributes and methods across all classes.

## 3. Success / Verification Criteria
- All requested headers are present and structured correctly.
- All Mermaid diagrams render correctly with valid syntax.
- `git diff origin/main` matches only the requested changes for epic-04-wasm-extensibility.md (and the updated implementation plan).
- Changes committed and pushed to origin/main.
