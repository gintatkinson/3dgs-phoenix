---
title: "WebAssembly Component Model Extensibility Epic"
type: "epic"
spec_source: "Architecture Specification"
generation_mode: "subagent"
issue_id: 247
---

# Epic: WebAssembly Component Model Extensibility

## 1. Context
To support third-party extensibility, custom network protocol parsers, and external billing integrations safely, the platform embeds a WebAssembly execution environment. The Global Coordinator embeds the Rust `wasmtime` runtime to execute sandboxed `.wasm` plugins. 

Rather than relying on legacy, unsafe shared libraries (`.dll`, `.dylib`, `.so`) or heavy subprocess overhead, the architecture utilizes the WebAssembly Component Model (WASI and WIT). 
- **Near-Native Execution**: The Wasmtime engine compiles Wasm bytecode directly into host machine instructions using the Cranelift JIT compiler.
- **Capability-Based Sandboxing**: Wasm plugins execute within a strictly constrained WASI environment. File system and network capabilities are not implicitly inherited from the host process. Access to specific directories or network sockets must be explicitly mapped and pre-opened during instantiation.
- **WIT Interfaces**: Instead of raw, low-level integer/pointer passing across the Foreign Function Interface (FFI) boundary, WebAssembly Interface Types (WIT) specify high-level types (records, variants, lists, results). The `wit-bindgen` tool generates standard, type-safe bindings for the Rust plugins and the host runtime.
- **Asynchronous Batching**: FFI transitions introduce overhead. To ensure 60 FPS UI rendering and coordinate streams are not blocked by high-frequency plugin communications, commands are batched in memory on both sides of the boundary before crossing.

---

## 2. Requirements & Checklist
- [ ] **Requirement 4.1 (Wasmtime Runtime Config & Cranelift JIT)**: The Global Coordinator must embed the Rust `wasmtime` runtime. The configuration must explicitly enable the Cranelift JIT compiler to compile WebAssembly code to native machine code on demand.
- [ ] **Requirement 4.2 (WASI Sandbox Permissions)**: The execution sandbox must isolate file system and network access. Directory handles and network sockets must be pre-opened and passed during context setup, rejecting any direct access to unauthorized paths or hosts.
- [ ] **Requirement 4.3 (WIT Interfaces & wit-bindgen)**: Plugin APIs must be declared using WIT schemas. Rust-based plugins must use `wit-bindgen` to compile bindings, ensuring structured data exchange (records, results) without manual FFI memory allocation or pointer arithmetic.
- [ ] **Requirement 4.4 (Asynchronous Batching)**: During high-frequency operations, telemetry and control commands crossing the FFI boundary must be batched into in-memory queues and processed asynchronously to prevent FFI latency from blocking the main execution thread or dropping frames.

---

## 3. Architecture and System Interaction Diagrams

### Subsystem Component Definition
The `WasmExtensibilitySubsystem` component defines the interfaces exposed to the coordinator and required from the plugins.

```mermaid
classDiagram
    class WasmExtensibilitySubsystem {
        <<component>>
        +loadPlugin(wasmBytes : ByteArray, config : SandboxConfig) PluginInstance [1]
        +executeCommand(pluginId : String, payload : String) String [1]
    }
    class PluginInstance {
        +String pluginId
        +Boolean isActive
        +callExport(funcName : String, args : List) Result
    }
    WasmExtensibilitySubsystem ..> PluginInstance : Instantiates
```

### System-Level UML Class Diagram
This diagram details the classes managing Wasmtime, WASI contexts, and the WIT-generated interfaces.

```mermaid
classDiagram
    class WasmtimeEngine {
        -Engine engine
        -Linker linker
        +initialize(enableJit : Boolean) Void
        +newStore(wasiCtx : WasiCtx) Store
    }
    class WasiSandboxConfig {
        +List~String~ allowedDirectories
        +List~String~ allowedHosts
        +buildWasiContext() WasiCtx
    }
    class PluginManager {
        -Map~String, PluginInstance~ loadedPlugins
        -WasmtimeEngine engine
        +loadPlugin(path : String, config : WasiSandboxConfig) String
        +unloadPlugin(id : String) Void
        +getPlugin(id : String) PluginInstance
    }
    class WitInterface {
        <<interface>>
        +parseBillingData(record : BillingRecord) BillingResult
        +streamTelemetryBatch(batch : TelemetryBatch) TelemetryResponse
    }
    class BillingPlugin {
        +validateInterface() Boolean
        +calculateMetrics(data : String) String
    }

    PluginManager o-- WasmtimeEngine
    PluginManager o-- WasiSandboxConfig
    PluginInstance o-- WitInterface
    BillingPlugin ..|> WitInterface
```

### System Interaction Diagram (Use Case UC-2)
The sequence of events when loading and executing a third-party billing plugin.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Coord as Global Coordinator
    participant Mgr as PluginManager
    participant Sandbox as WASI Sandbox
    participant JIT as Wasmtime Engine (Cranelift)
    participant Plugin as Billing Plugin (WIT)

    User->>Coord: Trigger Load Billing Plugin (.wasm)
    Coord->>Mgr: loadPlugin(wasmBytes, config)
    activate Mgr
    Mgr->>JIT: Compile bytecode (Cranelift JIT)
    activate JIT
    JIT-->>Mgr: Compiled Module
    deactivate JIT
    Mgr->>Sandbox: buildWasiContext(preopenedDirs, allowedHosts)
    activate Sandbox
    Sandbox-->>Mgr: WasiCtx Handle
    deactivate Sandbox
    Mgr->>Mgr: Instantiate & Link Imports
    Mgr-->>Coord: PluginInstance (ID: bill_01)
    deactivate Mgr

    Coord->>Plugin: execute calculateMetrics(record) (via WIT Interface)
    activate Plugin
    Note over Plugin: Sandboxed Execution
    Plugin->>Sandbox: Read Config File (Preopened Dir)
    Sandbox-->>Plugin: Config Data
    Plugin->>Plugin: Process Billing Logic
    Plugin-->>Coord: BillingResult
    deactivate Plugin
```

---

## 4. State Machine Definitions

The state transition model for Wasm plugins loaded within the host runtime.

```mermaid
stateDiagram-v2
    [*] --> Unloaded
    Unloaded --> Compiling : LoadPlugin(wasm_bytes)
    Compiling --> CompilationFailed : CraneliftError
    CompilationFailed --> Unloaded : Retry / Clean
    Compiling --> Instantiating : ModuleCompiled
    Instantiating --> ValidationFailed : WITInterfaceMismatch
    ValidationFailed --> Unloaded : Clean
    Instantiating --> Sandboxed : LinkSuccessful
    Sandboxed --> Active : StartPlugin
    Active --> Suspended : ResourceQuotaExceeded / Pause
    Suspended --> Active : Resume
    Active --> Terminated : UnloadPlugin / Crash
    Suspended --> Terminated : UnloadPlugin
    Terminated --> Unloaded : Clean
```

---

## 5. Specification Context

### Use Case UC-2: Loading a Third-Party Billing Plugin

- **Actor**: Global Coordinator / User
- **Trigger**: User installs a compiled `.wasm` extension representing a billing plugin.
- **Preconditions**:
  1. The `.wasm` module conforms to the pre-defined WIT interface structure.
  2. The Global Coordinator has initialized the `WasmtimeEngine` with Cranelift JIT.
- **Main Success Scenario**:
  1. The user requests the system to load the billing plugin from a specific directory.
  2. The `PluginManager` reads the plugin bytes and invokes the Cranelift compiler.
  3. The runtime builds a `WasiCtx` containing restricted directory permissions (e.g. read-only access to a specific local configuration folder) and denies network access.
  4. The runtime instantiates the compiled module, linking the imports via the WIT interface.
  5. The plugin is registered and activated.
  6. The Coordinator invokes `calculateMetrics` through the FFI boundary, passing structured billing logs.
  7. The plugin processes the logs and writes temporary reports inside the sandboxed directory.
  8. The plugin returns the calculated metrics to the Coordinator via a structured WIT response.
- **Postconditions**:
  1. The billing plugin remains loaded and sandboxed.
  2. The plugin has zero access to host environment variables or directories outside the designated sandbox.
  3. The host process remains isolated from any plugin memory safety issues.

---

### User Stories

#### US-4.1.1: Runtime initialization with Cranelift JIT
**As an** Application Administrator,  
**I want** the host process to initialize the Wasmtime JIT compiler,  
**So that** loaded WebAssembly modules can run at near-native execution speeds.

* **Requirement Reference**: Requirement 4.1
* **Acceptance Criteria**:
  * **Given** the Global App Coordinator is starting up,
  * **When** the `WasmtimeEngine` is instantiated,
  * **Then** the engine's configuration must have `cranelift` enabled as the compiler and JIT optimization level set to `speed`.
  * **And** loading a standard benchmark `.wasm` file must return a compiled executable module with a compilation latency of less than 150ms.

#### US-4.2.1: WASI filesystem capability constraint
**As a** Security Officer,  
**I want** third-party plugins to access only pre-approved folders on the host filesystem,  
**So that** plugins cannot read sensitive user documents or write malicious system files.

* **Requirement Reference**: Requirement 4.2
* **Acceptance Criteria**:
  * **Given** a WASM plugin has been configured with access to `/Users/perkunas/jail/3dgs-phoenix/app_flutter/assets/` as a pre-opened directory,
  * **When** the plugin executes a file-read command inside that path,
  * **Then** it must succeed and return the correct file content.
  * **When** the plugin attempts to open or write to `/etc/passwd` or `/Users/perkunas/.ssh`,
  * **Then** the WASI capability checks must reject the call, and the operation must fail with a `PermissionDenied` error.

#### US-4.2.2: WASI network capability isolation
**As a** Network Security Engineer,  
**I want** plugins to be restricted from making unauthorized network calls,  
**So that** proprietary billing or telemetry data is not leaked to external servers.

* **Requirement Reference**: Requirement 4.2
* **Acceptance Criteria**:
  * **Given** a plugin is initialized with network capabilities explicitly disabled in the `WasiSandboxConfig`,
  * **When** the plugin attempts to resolve an IP address or open a socket connection,
  * **Then** the runtime must intercept and terminate the operation, throwing a `SocketException` or sandbox violation.

#### US-4.3.1: WIT Bindgen data streaming type validation
**As a** Rust Plugin Developer,  
**I want** to specify plugin interfaces using WebAssembly Interface Types (WIT) and compile them with `wit-bindgen`,  
**So that** complex data models can be passed to and from the host without writing manual pointer/offset conversion code.

* **Requirement Reference**: Requirement 4.3
* **Acceptance Criteria**:
  * **Given** a WIT interface declaration defining a `record BillingRecord { id: string, amount: float64 }` and a `result<BillingResult, Error>` return type,
  * **When** the Rust plugin is compiled using the `wit-bindgen` macro,
  * **Then** the generated code must compile without errors.
  * **And** when the host passes a `BillingRecord` instance across the FFI boundary, the target fields must match precisely on the Rust side without manual memory allocations.

#### US-4.4.1: Asynchronous FFI batching queue execution
**As a** Core Performance Engineer,  
**I want** high-frequency plugin events to be batched and dispatched asynchronously,  
**So that** the FFI boundary crossing overhead does not block the 60 FPS UI rendering thread.

* **Requirement Reference**: Requirement 4.4
* **Acceptance Criteria**:
  * **Given** the application UI is rendering at 60 FPS and generating 200 telemetry updates per second,
  * **When** these telemetry events are sent to the Wasm subsystem,
  * **Then** the `PluginManager` must queue them in memory and dispatch them in batches (maximum frequency of 60 batch transfers per second).
  * **And** the average duration of the FFI call transition block must remain under 1ms, preserving the 16.6ms frame budget.

---

## 6. Source References
- Architectural Specification: [Architecture-spec-Cross-Platform-Rendering-and-WebAssembly.md](file:///Users/perkunas/jail/3dgs-phoenix/docs/architecture/Architecture-spec-Cross-Platform-Rendering-and-WebAssembly.md)
- Wasmtime Rust Config Reference: [wasmtime::Config docs](https://docs.wasmtime.dev/api/wasmtime/struct.Config.html)
- WebAssembly Component Model WIT Specs: [WIT By Example](https://component-model.bytecodealliance.org/design/wit-example.html)
- WASI Capability Design Principles: [WASM System Interface](https://wasi.dev/)
