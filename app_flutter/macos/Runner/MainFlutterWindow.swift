import Cocoa
import FlutterMacOS
import CoreVideo
import IOSurface

public class MacIosurfaceTexturePlugin: NSObject, FlutterPlugin, FlutterTexture {
    private let registry: FlutterTextureRegistry
    private var textureId: Int64 = 0
    private var ioSurface: IOSurfaceRef?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "3dgs.phoenix/texture_bridge", binaryMessenger: registrar.messenger)
        let registry = registrar.textures
        let instance = MacIosurfaceTexturePlugin(registry: registry)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getTextureId" {
            if self.textureId == 0 {
                self.textureId = self.registry.register(self)
            }
            result(self.textureId)
        } else if call.method == "updateFrame" {
            if let args = call.arguments as? [String: Any],
               let surfacePointerVal = args["ioSurfaceRef"] as? Int64 {
                if let rawPointer = UnsafeRawPointer(bitPattern: Int(surfacePointerVal)) {
                    let surface = unsafeBitCast(rawPointer, to: IOSurfaceRef.self)
                    self.ioSurface = surface
                    if self.textureId != 0 {
                        self.registry.textureFrameAvailable(self.textureId)
                    }
                }
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing ioSurfaceRef", details: nil))
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let ioSurface = self.ioSurface else { return nil }
        var pixelBuffer: Unmanaged<CVPixelBuffer>?
        let status = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            ioSurface,
            nil,
            &pixelBuffer
        )
        if status == kCVReturnSuccess, let buffer = pixelBuffer {
            return buffer
        }
        return nil
    }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let registrar = flutterViewController.registrar(forPlugin: "MacIosurfaceTexturePlugin")
    MacIosurfaceTexturePlugin.register(with: registrar)

    super.awakeFromNib()
  }
}
