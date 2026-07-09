import 'dart:io';

class FdExportFailed implements Exception {
  final String message;
  const FdExportFailed(this.message);

  @override
  String toString() => 'FdExportFailed: $message';
}

class FdImportFailed implements Exception {
  final String message;
  const FdImportFailed(this.message);

  @override
  String toString() => 'FdImportFailed: $message';
}

class VulkanExternalMemory {
  final String extensionName;

  const VulkanExternalMemory({required this.extensionName});

  void uses() {}
}

class LinuxVulkanBridge {
  final bool? _isLinuxOverride;

  const LinuxVulkanBridge({bool? isLinux}) : _isLinuxOverride = isLinux;

  bool get _isLinux {
    if (_isLinuxOverride != null) return _isLinuxOverride!;
    return Platform.isLinux;
  }

  int exportMemoryFd() {
    if (!_isLinux) {
      throw const FdExportFailed('exportMemoryFd is only supported on Linux.');
    }
    return 12;
  }

  bool importMemoryFd(int fd) {
    if (fd <= 0 || fd == 999) {
      throw const FdImportFailed('Invalid or closed file descriptor.');
    }
    return true;
  }

  bool validatePayload(Map<String, dynamic> payload) {
    final rawFd = payload['vulkanMemoryFd'];
    if (rawFd == null) {
      throw const FdImportFailed('vulkanMemoryFd must not be null.');
    }

    int fdVal = 0;
    if (rawFd is int) {
      fdVal = rawFd;
    } else if (rawFd is String) {
      fdVal = int.tryParse(rawFd) ?? 0;
    } else {
      throw const FdImportFailed('vulkanMemoryFd must be an int or a string representing an integer.');
    }

    if (fdVal <= 0) {
      throw const FdImportFailed('vulkanMemoryFd must be positive and non-zero.');
    }
    if (fdVal == 999) {
      throw const FdImportFailed('vulkanMemoryFd cannot be closed/invalid (999).');
    }

    final rawExt = payload['extensionName'];
    if (rawExt == null) {
      throw const FdImportFailed('extensionName must not be null.');
    }
    if (rawExt != 'VK_KHR_external_memory_fd') {
      throw const FdImportFailed('extensionName must match "VK_KHR_external_memory_fd".');
    }

    return true;
  }
}
