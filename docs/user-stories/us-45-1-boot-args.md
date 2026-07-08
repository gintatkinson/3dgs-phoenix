---
title: "CommandLine Scene Argument Routing"
type: "user-story"
spec_source: "Project Constitution"
generation_mode: "subagent"
epic: "Epic 1: Platform-Agnostic Scene-Based Lifecycle (Windowing) Epic"
---

# User Story US-45-1: CommandLine Scene Argument Routing

## Parent Epic
- [ ] #247 - [Epic 1: Platform-Agnostic Scene-Based Lifecycle (Windowing) Epic](https://github.com/gintatkinson/3dgs-phoenix/blob/main/docs/epics/epic-01-scene-lifecycle.md) (Aggregates multi-process windowing logic)

## Domain Object Mapping
- **Primary Domain Objects:** SceneBootstrapper, SceneViewWidget
- **Actor/Role:** coordinator : Coordinator (Host main application process coordinator)

## BDD Scenario (OOA/OOD Realization)
**Given** the app is started with a list of command line arguments
**When** the coordinator calls SceneBootstrapper.boot()
**Then** the bootstrapper parses the arguments, and if --scene=[id] is present, instantiates and builds SceneViewWidget with the target sceneId, returning true. If --scene is not present, it returns false and boots the default MainShell.

## UML Sequence Diagram
```mermaid
sequenceDiagram
    autonumber
    actor coordinator as "coordinator : Coordinator"
    participant bootstrapper as "bootstrapper : SceneBootstrapper"
    participant widget as "widget : SceneViewWidget"

    coordinator->>bootstrapper: boot(args: StringArray)
    alt [args contains "--scene=[id]"]
        bootstrapper->>widget: build()
        widget-->bootstrapper: widgetView : Widget
        bootstrapper-->coordinator: isBooted : Boolean
    else [args does not contain "--scene=[id]"]
        bootstrapper-->coordinator: isBooted : Boolean
    end
```

## Required Features
- [ ] #250 - [Feature 45: Isolated Scene Boot](https://github.com/gintatkinson/3dgs-phoenix/blob/main/docs/features/feat-45-isolated-scene-boot.md) (CommandLine Scene Argument Routing)

## Source References
Structural Schema: `docs/architecture/Architecture-spec-Cross-Platform-Rendering-and-WebAssembly.md`
Normative Specification: Project Constitution
