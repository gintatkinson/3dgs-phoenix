# Implementation Plan - Epic 4: WebAssembly Component Model Extensibility Linter Fixes

## 1. Objectives
- Fix Mermaid class diagram linter violations in `/Users/perkunas/jail/3dgs-phoenix/docs/epics/epic-04-wasm-extensibility.md`.
- Change attribute syntax of all classes from `-name : type` to standard UML format without colons: `visibility type name [multiplicity]`.
- Change realization connector `..|>` to generalization connector `<|--` under relationships section.

## 2. File Modifications

### `docs/epics/epic-04-wasm-extensibility.md`
- Replace attributes:
  - `-engine : String [1]` with `-String engine [1]`
  - `-linker : String [1]` with `-String linker [1]`
  - `-loadedPlugins : PluginInstance [0..*]` with `-PluginInstance loadedPlugins [0..*]`
  - `-engine : WasmtimeEngine [1]` with `-WasmtimeEngine engine [1]`
- Replace connector:
  - `BillingPlugin ..|> WitInterface` with `WitInterface <|-- BillingPlugin`

## 3. Success / Verification Criteria
- `docs/epics/epic-04-wasm-extensibility.md` renders correctly.
- All modifications are cleanly staged, committed, and pushed to origin/main.
- `git diff origin/main` shows no changes.
