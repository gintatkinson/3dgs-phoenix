---
title: "Implementation Profile — macOS"
project: "3DGS Phoenix"
tier: implementation
platform: macos
created: "2026-07-10"
last_updated: "2026-07-10"
---

# Implementation Profile: macOS

> This document governs feature implementation on macOS only.
> Read alongside `.pipeline/constitution.md` (functional layer).

## Platform & Stack

- **Flutter:** Dart with strict null checks, strong mode
- **Swift:** macOS native plugin (MainFlutterWindow.swift)
- **C++ bridge:** cesium-native via CMake (cesium_native_bridge/)
- No additional dependency constraints beyond existing pubspec.yaml

## Coding Standards

- **C++:** Standard C++17 naming conventions. `#pragma once` headers.
- **Dart:** UpperCamelCase classes, lowerCamelCase methods/variables. `late` where appropriate. No `dynamic` unless unavoidable.
- **Swift:** Standard Swift naming. IOSurface/CVPixelBuffer CF types managed with CFRelease.
- **File naming:** C++: snake_case. Dart: snake_case. Swift: PascalCase.

## Testing Mandates

- **TDD Enforcement:** Per micro-task RED-GREEN-REFACTOR cycle mandatory
- **Framework:** Flutter: `flutter test` for Dart unit tests. C++: No automated test runner available (verify via build + runtime test).
- **Threshold:** Maintain current 209/209 Dart test pass count. No coverage percentage target.
- **Build verification:** `flutter analyze` must pass with zero errors.

## Build & Deployment

- **Bridge compilation:** `cd cesium_native_bridge && cmake --build build --target cesium_native_bridge`
- **Flutter analyze:** `flutter analyze` (zero errors)
- **Flutter test:** `flutter test` (all passing)
- **Flutter build:** `flutter build macos --release`
- **No CI/CD pipeline**

## Security & Ops

- **API keys:** Cesium ion token resolved via the environment variable `CESIUM_ION_TOKEN` — never in plaintext code files
- **No auth provider**
- **No CORS/CSP** (desktop application, not web-hosted)
