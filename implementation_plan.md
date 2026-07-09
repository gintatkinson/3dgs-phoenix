# Implementation Plan: Feature 49 (Linux Vulkan External Memory Interop)

This feature implements the Linux Vulkan External Memory Interop bridge classes and verification tests.

## Proposed Changes

### Component: Domain & Native Bridge

#### [NEW] [linux_vulkan_bridge.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/lib/domain/cesium_3d/native/linux_vulkan_bridge.dart)
- Implement `FdExportFailed` implementing `Exception`.
- Implement `FdImportFailed` implementing `Exception`.
- Implement `VulkanExternalMemory`:
  - Fields: `final String extensionName`.
  - Constructor: `const VulkanExternalMemory({required this.extensionName})`.
  - Method: `void uses() {}`.
- Implement `LinuxVulkanBridge`:
  - Fields: `final bool? _isLinuxOverride`.
  - Constructor: `const LinuxVulkanBridge({bool? isLinux}) : _isLinuxOverride = isLinux;`
  - Getter: `bool get _isLinux` to detect Linux platform (falling back to `Platform.isLinux` if override is null).
  - Method: `int exportMemoryFd()`:
    - Checks platform: if not on Linux (using `_isLinux`), throws `FdExportFailed`.
    - Returns mock file descriptor integer `12`.
  - Method: `bool importMemoryFd(int fd)`:
    - If `fd <= 0` or `fd == 999` (closed/invalid FD), throws `FdImportFailed`.
    - Returns true.
  - Method: `bool validatePayload(Map<String, dynamic> payload)`:
    - Parses and validates payload schema.
    - Constraints validation:
      - `vulkanMemoryFd` must be positive and non-zero (throws `FdImportFailed` if <= 0). If it is `999` (closed FD), throws `FdImportFailed`.
      - `extensionName` must be present and match `"VK_KHR_external_memory_fd"`. If not, throws `FdImportFailed`.
      - If valid, returns true.

---

### Component: Verification & Test Suite

#### [NEW] [linux_vulkan_interop_test.dart](file:///Users/perkunas/jail/3dgs-phoenix/app_flutter/test/cesium_3d/linux_vulkan_interop_test.dart)
- Add unit tests verifying:
  - Given the application is running on Linux, the graphics bridge allocates/validates payload with shared file descriptor and extension `"VK_KHR_external_memory_fd"` correctly.
  - Passing an invalid or closed file descriptor (e.g. `999` or negative) throws a `FdImportFailed` exception.
  - Verify `exportMemoryFd` behaves correctly under Linux vs non-Linux environments.
  - Verify fields initialization check on `VulkanExternalMemory`.

---

## Verification Plan

### Automated Tests
- Run the newly created test suite:
  ```bash
  flutter test test/cesium_3d/linux_vulkan_interop_test.dart
  ```
