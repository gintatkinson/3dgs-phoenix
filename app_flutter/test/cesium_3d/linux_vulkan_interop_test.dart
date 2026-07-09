import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/domain/cesium_3d/native/linux_vulkan_bridge.dart';

void main() {
  group('Linux Vulkan External Memory Interop Tests', () {
    test('VulkanExternalMemory fields initialization check', () {
      const extMem = VulkanExternalMemory(extensionName: 'VK_KHR_external_memory_fd');
      expect(extMem.extensionName, equals('VK_KHR_external_memory_fd'));
      extMem.uses();
    });

    test('exportMemoryFd behaves correctly under Linux vs non-Linux environments', () {
      const bridgeLinux = LinuxVulkanBridge(isLinux: true);
      expect(bridgeLinux.exportMemoryFd(), equals(12));

      const bridgeNonLinux = LinuxVulkanBridge(isLinux: false);
      expect(() => bridgeNonLinux.exportMemoryFd(), throwsA(isA<FdExportFailed>()));
    });

    test('importMemoryFd throws FdImportFailed on invalid or closed file descriptor', () {
      const bridge = LinuxVulkanBridge();

      expect(bridge.importMemoryFd(12), isTrue);

      expect(() => bridge.importMemoryFd(999), throwsA(isA<FdImportFailed>()));

      expect(() => bridge.importMemoryFd(-5), throwsA(isA<FdImportFailed>()));

      expect(() => bridge.importMemoryFd(0), throwsA(isA<FdImportFailed>()));
    });

    test('Given the application is running on Linux, the graphics bridge allocates/validates payload with shared file descriptor and extension correctly', () {
      const bridge = LinuxVulkanBridge(isLinux: true);

      final payload = {
        'vulkanMemoryFd': 12,
        'extensionName': 'VK_KHR_external_memory_fd',
      };

      expect(bridge.validatePayload(payload), isTrue);
    });

    test('validatePayload parses string file descriptor correctly', () {
      const bridge = LinuxVulkanBridge(isLinux: true);

      final payload = {
        'vulkanMemoryFd': '12',
        'extensionName': 'VK_KHR_external_memory_fd',
      };

      expect(bridge.validatePayload(payload), isTrue);
    });

    test('validatePayload throws FdImportFailed on invalid or closed file descriptors', () {
      const bridge = LinuxVulkanBridge(isLinux: true);

      expect(
        () => bridge.validatePayload({
          'extensionName': 'VK_KHR_external_memory_fd',
        }),
        throwsA(isA<FdImportFailed>()),
      );

      expect(
        () => bridge.validatePayload({
          'vulkanMemoryFd': true,
          'extensionName': 'VK_KHR_external_memory_fd',
        }),
        throwsA(isA<FdImportFailed>()),
      );

      expect(
        () => bridge.validatePayload({
          'vulkanMemoryFd': 'not_an_int',
          'extensionName': 'VK_KHR_external_memory_fd',
        }),
        throwsA(isA<FdImportFailed>()),
      );

      expect(
        () => bridge.validatePayload({
          'vulkanMemoryFd': -1,
          'extensionName': 'VK_KHR_external_memory_fd',
        }),
        throwsA(isA<FdImportFailed>()),
      );

      expect(
        () => bridge.validatePayload({
          'vulkanMemoryFd': 0,
          'extensionName': 'VK_KHR_external_memory_fd',
        }),
        throwsA(isA<FdImportFailed>()),
      );

      expect(
        () => bridge.validatePayload({
          'vulkanMemoryFd': 999,
          'extensionName': 'VK_KHR_external_memory_fd',
        }),
        throwsA(isA<FdImportFailed>()),
      );
    });

    test('validatePayload throws FdImportFailed when extensionName is missing or incorrect', () {
      const bridge = LinuxVulkanBridge(isLinux: true);

      expect(
        () => bridge.validatePayload({
          'vulkanMemoryFd': 12,
        }),
        throwsA(isA<FdImportFailed>()),
      );

      expect(
        () => bridge.validatePayload({
          'vulkanMemoryFd': 12,
          'extensionName': 'VK_KHR_external_memory_other',
        }),
        throwsA(isA<FdImportFailed>()),
      );
    });
  });
}
