# **Software Architectural Specification: Cross-Platform 3D Network Visualization & Extensibility Platform**

## **1.0 Executive Summary**

This document serves as the master architectural specification for a platform-agnostic (macOS, Windows, Linux) desktop application designed for enterprise 3D network topology visualization. It unifies declarative UI (Flutter), high-fidelity headless 3D graphics (Unreal Engine/Cesium), native geospatial rendering (cesium\_3d\_native/Flutter Scene), and secure, dynamically loaded execution environments (WebAssembly/Wasmtime).  
**Primary Objective:** To provide downstream engineering agents with structured technical requirements, component boundaries, and use cases to systematically generate Epics, User Stories, and UML design artifacts.

## **2.0 System Architecture Overview**

The system employs a multi-process, Hub-and-Spoke architecture to ensure absolute fault segregation and zero-copy rendering performance.

### **2.1 Core Subsystems**

1. **Global App Coordinator (Dart/Flutter):** The primary host process. Manages overarching application state, network connections, and the Wasmtime runtime sandbox.  
2. **Scene Delegates (Dart/Flutter):** Independent OS processes or Flutter engines responsible for rendering isolated UI windows (replicating UIWindowScene paradigms).  
3. **Headless Rendering Daemon (C++/Unreal Engine):** An offscreen process running Cesium for Unreal. Streams massive 3D tilesets and outputs raw GPU memory handles.  
4. **Lite-Mode Native Renderer (Dart FFI/C++):** An in-process rendering pipeline using cesium\_3d\_native and flutter\_scene for lightweight, hardware-accelerated 3D rendering without the Unreal Engine overhead.  
5. **Extensibility Sandbox (Rust/Wasmtime):** An embedded WebAssembly runtime utilizing the Component Model (WASI and WIT) to safely execute third-party business logic and network protocols.1

## **3.0 Epics & Subsystem Specifications**

*Agents should use this section to generate specific Jira/Linear Epics and granular User Stories.*

### **Epic 1: Platform-Agnostic Scene-Based Lifecycle (Windowing)**

**Context:** The application must support multiple independent windows (scenes) that can crash or be closed without affecting the main application, utilizing Flutter's multi-engine capabilities.

* **Requirement 1.1 (Process Spawning):** The Global App Coordinator must parse command-line arguments main(List\<String\> args) to dictate engine behavior. If \--scene=\[id\] is passed, the engine boots into a highly isolated SceneViewWidget() lifecycle.  
* **Requirement 1.2 (Fault Segregation):** Scenes must communicate with the Coordinator via local gRPC Unix Domain Sockets (UDS). If an Impeller shader faults in Scene A, the OS-level isolation must guarantee the Coordinator and Scene B remain active.  
* **Requirement 1.3 (macOS Compliance):** On macOS, isolated scene processes must be launched as helper apps with the LSUIElement key set to true in their Info.plist to prevent redundant Dock icons.

### **Epic 2: Enterprise 3D Rendering (Zero-Copy GPU Texture Bridge)**

**Context:** For maximum visual fidelity, the system relies on an offscreen Unreal Engine instance streaming Cesium ion datasets. The rendered frames must be transferred to the Flutter UI without CPU memory copies.

* **Requirement 2.1 (Headless Unreal Orchestration):** The coordinator must spawn Unreal Engine using the \-RenderOffscreen argument to bypass OS window managers.3  
* **Requirement 2.2 (Windows DXGI Interop):** On Windows, the Unreal DirectX 12/Vulkan output must be exported as a DXGI shared handle. Flutter must map this using kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle to sample VRAM directly.4  
* **Requirement 2.3 (macOS IOSurface Interop):** On macOS, the engine must output to a CVPixelBuffer backed by an IOSurfaceRef.6 To support Apple Silicon, the buffer must be configured with MTLStorageModeShared.7  
* **Requirement 2.4 (Linux Vulkan Interop):** On Linux, the offscreen engine must expose memory via the VK\_KHR\_external\_memory\_fd extension, passing the file descriptor over the UDS bridge to the Flutter texture registrar.

### **Epic 3: Native "Lite Mode" Geospatial Rendering**

**Context:** For scenarios where the Unreal Engine daemon is too heavy, the application must natively render 3D network topologies within the Flutter process.

* **Requirement 3.1 (Spatial Logic Engine):** Integrate the cesium\_3d\_native Dart package via FFI. This layer is responsible for requesting 3D Tiles from Cesium ion, culling invisible tiles based on camera frustum, and outputting in-memory glTF meshes.  
* **Requirement 3.2 (Coordinate Transformation):** Implement high-precision FFI math to translate Earth-Centered, Earth-Fixed (ECEF) coordinates from Cesium into local Cartesian coordinates.  
* **Requirement 3.3 (Native UI Compositing):** The translated glTF meshes must be passed to the flutter\_scene package, which utilizes the flutter\_gpu low-level API (Impeller backend) to render Physically Based Rendering (PBR) assets directly onto the Flutter canvas.

### **Epic 4: WebAssembly Component Model Extensibility**

**Context:** To support custom network protocol parsers and third-party plugins securely.

* **Requirement 4.1 (Wasmtime Runtime):** The Global Coordinator must embed the Rust wasmtime runtime.8 The cranelift JIT compiler should be enabled for near-native execution speeds.  
* **Requirement 4.2 (WASI Sandbox):** Plugins must run inside a strictly defined WebAssembly System Interface (WASI) context. Network access and file system access (e.g., local database directories) must be explicitly granted per-plugin.1  
* **Requirement 4.3 (WIT Interfaces):** Plugins must adhere to WebAssembly Interface Types (WIT). The interface must define complex types (e.g., records, results) to handle asynchronous data streams without manual memory marshaling.2 Use wit-bindgen to automate Rust bindings.9  
* **Requirement 4.4 (Asynchronous Batching):** To prevent Foreign Function Interface (FFI) bottlenecks during 60 FPS render loops, plugin commands must be aggressively batched in memory before crossing the WIT boundary.10

## **4.0 Use Case Specifications**

*Agents should use these use cases to map behavioral tests and validation criteria.*  
**UC-1: Opening a Multi-Node Topology View (Multi-Engine)**

* **Trigger:** User selects a complex optical ring in the UI and clicks "Open in 3D Viewer".  
* **Action:** Coordinator parses the request and executes Process.start() passing \--scene=3d\_viewer \--target\_id=ring\_01.  
* **Outcome:** A new window opens. The new Flutter engine queries the coordinator via gRPC, receives the topology payload, and initializes either the Lite Mode (flutter\_scene) or Enterprise Mode (Unreal) based on system hardware resources.

**UC-2: Loading a Third-Party Billing Plugin (Wasmtime)**

* **Trigger:** User installs a compiled .wasm extension for a proprietary billing system.  
* **Action:** The Wasmtime engine evaluates the plugin against the pre-defined .wit interface.  
* **Outcome:** If the interface matches, the plugin is loaded into the WASI sandbox. It receives a restricted directory handle and calculates billing metrics, passing the safe result back to the Dart UI without accessing host OS APIs.

**UC-3: Handling an Unreal Engine Rendering Crash**

* **Trigger:** A malformed Photorealistic 3D Tile from Cesium ion causes a segmentation fault in the headless Unreal process.  
* **Action:** The Flutter Texture widget freezes on the last valid GPU frame. The Coordinator detects the child process exit code.  
* **Outcome:** The Coordinator logs the error, reboots the Unreal Engine daemon, requests a fresh DXGI/IOSurface handle, and hot-swaps the new memory address into the active Flutter Texture widget seamlessly.

## **5.0 UML Artifact Generation Guidelines**

*Instructions for architectural modeling agents to construct visual documentation:*

1. **Component Diagram:**  
   * *Nodes:* Flutter Main Engine, Flutter Scene Engines (xN), Wasmtime Runtime, Wasm Plugins, Unreal Headless Engine, Cesium ion API.  
   * *Edges:* gRPC over UDS (Inter-Flutter), FFI Boundary (Dart \<-\> Wasmtime), Zero-Copy Texture Handle (Unreal \<-\> Flutter Scene Engine).  
2. **Sequence Diagram (Render Loop):**  
   * *Actors:* User, SceneViewWidget, cesium\_3d\_native (C++), flutter\_scene (Dart), Impeller (GPU).  
   * *Flow:* User Pans Map \-\> Update Camera \-\> FFI Call to Cesium C++ \-\> Cesium Culls Tiles \-\> Returns glTF \-\> Dart Translates ECEF \-\> flutter\_scene draws via flutter\_gpu.  
3. **Deployment Diagram:**  
   * *Nodes:* Workstation (Windows/macOS/Linux).  
   * *Artifacts:* Main Executable (.exe/.app), Helper Process Executables, Embedded .wasm modules, Embedded Unreal Engine Binaries.

## **6.0 Antigravity Orchestration & Implementation Plan**

To execute this complex polyglot MVP, engineering teams will utilize **Google Antigravity 2.0**. Agents must strictly adhere to the following workflow tracking:

1. **Project Scaffolding:** The Antigravity Agent Manager handles four synchronized workflows (Rust Daemon, Flutter UI, Unreal Headless, Native Dart FFI).  
2. **Artifact Generation:** Before generating code, agents must produce a **Task List** and a detailed **Implementation Plan** mapped to the Epics in Section 3.0.  
3. **Repository Governance:** The agent connects via the **GitHub MCP Server** to autonomously initialize the repository, stage generated code, and commit via git push.  
4. **Verification:** Upon completing a module, the agent produces a **Walkthrough** and **Screenshots** documenting the active 3D visualization within the host OS.

#### **Works cited**

1. Wasmtime Example \- wasm-dbms, accessed on July 3, 2026, [https://wasm-dbms.cc/guides/wasmtime-example.html](https://wasm-dbms.cc/guides/wasmtime-example.html)  
2. WIT By Example \- The WebAssembly Component Model, accessed on July 3, 2026, [https://component-model.bytecodealliance.org/design/wit-example.html](https://component-model.bytecodealliance.org/design/wit-example.html)  
3. Getting Started with Multi-Process Rendering in Unreal Engine \- Epic Games Developers, accessed on July 3, 2026, [https://dev.epicgames.com/documentation/unreal-engine/getting-started-with-multi-process-rendering-in-unreal-engine?lang=en-US](https://dev.epicgames.com/documentation/unreal-engine/getting-started-with-multi-process-rendering-in-unreal-engine?lang=en-US)  
4. Flutter Windows Embedder: flutter::GpuSurfaceTexture Class Reference, accessed on July 3, 2026, [https://api.flutter.dev/windows-embedder/classflutter\_1\_1\_gpu\_surface\_texture.html](https://api.flutter.dev/windows-embedder/classflutter_1_1_gpu_surface_texture.html)  
5. Flutter Windows Embedder: flutter::testing Namespace Reference, accessed on July 3, 2026, [https://api.flutter.dev/windows-embedder/namespaceflutter\_1\_1testing.html](https://api.flutter.dev/windows-embedder/namespaceflutter_1_1testing.html)  
6. iosurface | Apple Developer Documentation, accessed on July 3, 2026, [https://developer.apple.com/documentation/metal/mtltexture/iosurface](https://developer.apple.com/documentation/metal/mtltexture/iosurface)  
7. \[Impeller\] Metal validation error when creating textures when run in Designed For iPad mode \#139147 \- GitHub, accessed on July 3, 2026, [https://github.com/flutter/flutter/issues/139147](https://github.com/flutter/flutter/issues/139147)  
8. Config in wasmtime \- Rust, accessed on July 3, 2026, [https://docs.wasmtime.dev/api/wasmtime/struct.Config.html](https://docs.wasmtime.dev/api/wasmtime/struct.Config.html)  
9. GitHub \- bytecodealliance/wit-bindgen: A language binding generator for WebAssembly interface types, accessed on July 3, 2026, [https://github.com/bytecodealliance/wit-bindgen](https://github.com/bytecodealliance/wit-bindgen)  
10. Building a dynamically-linked plugin system in Rust \- Reddit, accessed on July 3, 2026, [https://www.reddit.com/r/rust/comments/1d3g2c9/building\_a\_dynamicallylinked\_plugin\_system\_in\_rust/](https://www.reddit.com/r/rust/comments/1d3g2c9/building_a_dynamicallylinked_plugin_system_in_rust/)