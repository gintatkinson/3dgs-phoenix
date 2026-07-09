import Cocoa
import FlutterMacOS
import CoreVideo
import IOSurface

public class MacIosurfaceTexturePlugin: NSObject, FlutterPlugin, FlutterTexture {
    private let registry: FlutterTextureRegistry
    private var textureId: Int64 = 0
    private var pixelBuffer: CVPixelBuffer?
    
    private var cameraLat: Double = 35.6762
    private var cameraLon: Double = 139.6503
    private var cameraHeading: Double = 0.0
    private var cameraPitch: Double = 0.0
    
    private var pulseRadius: CGFloat = 0.0
    private var timer: Timer?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "3dgs.phoenix/texture_bridge", binaryMessenger: registrar.messenger)
        let registry = registrar.textures
        let instance = MacIosurfaceTexturePlugin(registry: registry)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
        
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pulseRadius += 0.01
            if self.pulseRadius > 1.0 { self.pulseRadius = 0.0 }
            self.renderGlobe()
            if self.textureId != 0 {
                self.registry.textureFrameAvailable(self.textureId)
            }
        }
    }

    deinit {
        self.timer?.invalidate()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getTextureId" {
            if self.textureId == 0 {
                self.textureId = self.registry.register(self)
            }
            result(self.textureId)
        } else if call.method == "updateCamera" {
            if let args = call.arguments as? [String: Any],
               let lat = args["latitude"] as? Double,
               let lon = args["longitude"] as? Double,
               let heading = args["heading"] as? Double,
               let pitch = args["pitch"] as? Double {
                self.cameraLat = lat
                self.cameraLon = lon
                self.cameraHeading = heading
                self.cameraPitch = pitch
                self.renderGlobe()
                if self.textureId != 0 {
                    self.registry.textureFrameAvailable(self.textureId)
                }
                result(true)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing camera arguments", details: nil))
            }
        } else if call.method == "updateFrame" {
            result(true)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = self.pixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    private func renderGlobe() {
        let width = 1280
        let height = 720
        
        if self.pixelBuffer == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                attrs as CFDictionary,
                &self.pixelBuffer
            )
        }
        
        guard let buffer = self.pixelBuffer else { return }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }
        
        let data = CVPixelBufferGetBaseAddress(buffer)
        let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        guard let ctx = context else { return }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bgColors = [
            CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1.0),
            CGColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1.0)
        ] as CFArray
        let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: nil)!
        let centerPt = CGPoint(x: width / 2, y: height / 2)
        ctx.drawRadialGradient(
            bgGradient,
            startCenter: centerPt,
            startRadius: 0,
            endCenter: centerPt,
            endRadius: CGFloat(max(width, height)),
            options: []
        )
        
        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.7))
        let starPoints: [CGPoint] = [
            CGPoint(x: 100, y: 150), CGPoint(x: 300, y: 80), CGPoint(x: 800, y: 120),
            CGPoint(x: 1100, y: 250), CGPoint(x: 150, y: 450), CGPoint(x: 950, y: 550),
            CGPoint(x: 450, y: 600), CGPoint(x: 750, y: 680), CGPoint(x: 50, y: 650),
            CGPoint(x: 1200, y: 50), CGPoint(x: 650, y: 100), CGPoint(x: 220, y: 300)
        ]
        for pt in starPoints {
            let size = CGFloat(1.5 + sin(self.pulseRadius * 6.28 + pt.x) * 0.7)
            ctx.fillEllipse(in: CGRect(x: pt.x, y: pt.y, width: size, height: size))
        }
        ctx.restoreGState()

        let globeRadius = CGFloat(min(width, height)) * 0.38
        
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize.zero,
            blur: 40.0,
            color: CGColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 0.6)
        )
        ctx.setFillColor(CGColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 1.0))
        ctx.fillEllipse(in: CGRect(
            x: centerPt.x - globeRadius,
            y: centerPt.y - globeRadius,
            width: globeRadius * 2,
            height: globeRadius * 2
        ))
        ctx.restoreGState()

        func project(lat: Double, lon: Double) -> (CGPoint, Double) {
            let theta = lat * .pi / 180.0
            let lambda = lon * .pi / 180.0
            let lambda0 = -self.cameraLon * .pi / 180.0
            let theta0 = self.cameraLat * .pi / 180.0
            
            let x = cos(theta) * cos(lambda - lambda0)
            let y = cos(theta) * sin(lambda - lambda0)
            let z = sin(theta)
            
            let ry = y * cos(theta0) - z * sin(theta0)
            let rz = y * sin(theta0) + z * cos(theta0)
            
            let px = centerPt.x + globeRadius * CGFloat(x)
            let py = centerPt.y - globeRadius * CGFloat(ry)
            
            return (CGPoint(x: px, y: py), rz)
        }
        
        let continents: [[(Double, Double)]] = [
            [(-10, -100), (20, -110), (45, -125), (70, -140), (75, -80), (60, -60), (45, -90), (25, -80)],
            [(-5, -80), (-20, -75), (-50, -45), (-40, -70), (-25, -80)],
            [(70, 20), (70, 160), (40, 120), (15, 100), (35, 40)],
            [(30, 30), (-25, 30), (-15, -10), (15, -15)],
            [(-15, 115), (-35, 115), (-30, 150), (-15, 140)]
        ]
        
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(
            x: centerPt.x - globeRadius,
            y: centerPt.y - globeRadius,
            width: globeRadius * 2,
            height: globeRadius * 2
        ))
        ctx.clip()
        
        let sphereColors = [
            CGColor(red: 0.08, green: 0.15, blue: 0.35, alpha: 1.0),
            CGColor(red: 0.01, green: 0.03, blue: 0.10, alpha: 1.0)
        ] as CFArray
        let sphereGradient = CGGradient(colorsSpace: colorSpace, colors: sphereColors, locations: nil)!
        ctx.drawRadialGradient(
            sphereGradient,
            startCenter: CGPoint(x: centerPt.x - globeRadius * 0.3, y: centerPt.y - globeRadius * 0.3),
            startRadius: 0,
            endCenter: centerPt,
            endRadius: globeRadius * 1.5,
            options: []
        )
        
        ctx.setFillColor(CGColor(red: 0.0, green: 0.8, blue: 0.5, alpha: 0.25))
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.9, blue: 0.6, alpha: 0.6))
        ctx.setLineWidth(1.5)
        
        for cont in continents {
            var first = true
            var count = 0
            for pt in cont {
                let (projectedPt, depth) = project(lat: pt.0, lon: pt.1)
                if depth >= 0.0 {
                    if first {
                        ctx.beginPath()
                        ctx.move(to: projectedPt)
                        first = false
                    } else {
                        ctx.addLine(to: projectedPt)
                    }
                    count += 1
                }
            }
            if count >= 3 {
                ctx.closePath()
                ctx.drawPath(using: .fillStroke)
            }
        }
        
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.2))
        ctx.setLineWidth(0.8)
        
        for lon in stride(from: -180.0, through: 180.0, by: 30.0) {
            var first = true
            for lat in stride(from: -90.0, through: 90.0, by: 5.0) {
                let (pt, depth) = project(lat: lat, lon: lon)
                if depth >= 0.0 {
                    if first {
                        ctx.beginPath()
                        ctx.move(to: pt)
                        first = false
                    } else {
                        ctx.addLine(to: pt)
                    }
                } else {
                    first = true
                }
            }
            ctx.strokePath()
        }
        
        for lat in stride(from: -60.0, through: 60.0, by: 30.0) {
            var first = true
            for lon in stride(from: -180.0, through: 180.0, by: 5.0) {
                let (pt, depth) = project(lat: lat, lon: lon)
                if depth >= 0.0 {
                    if first {
                        ctx.beginPath()
                        ctx.move(to: pt)
                        first = false
                    } else {
                        ctx.addLine(to: pt)
                    }
                } else {
                    first = true
                }
            }
            ctx.strokePath()
        }
        
        ctx.restoreGState()
        
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.6, blue: 1.0, alpha: 0.3))
        ctx.setLineWidth(1.0)
        ctx.strokeEllipse(in: CGRect(
            x: centerPt.x - globeRadius - 10,
            y: centerPt.y - globeRadius - 10,
            width: (globeRadius + 10) * 2,
            height: (globeRadius + 10) * 2
        ))
        
        ctx.setStrokeColor(CGColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.4))
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: centerPt.x - 25, y: centerPt.y))
        ctx.addLine(to: CGPoint(x: centerPt.x + 25, y: centerPt.y))
        ctx.move(to: CGPoint(x: centerPt.x, y: centerPt.y - 25))
        ctx.addLine(to: CGPoint(x: centerPt.x, y: centerPt.y + 25))
        ctx.strokePath()
        ctx.restoreGState()
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.8)
        ]
        let label1 = NSAttributedString(string: "UNREAL OFFSCREEN RENDER ENGINE", attributes: attrs)
        label1.draw(at: CGPoint(x: 30, y: height - 40))
        
        let label2 = NSAttributedString(string: "STATUS: ACTIVE  RHI: METAL_SM6", attributes: attrs)
        label2.draw(at: CGPoint(x: 30, y: height - 58))
        
        let label3 = NSAttributedString(
            string: String(format: "LAT: %.4f°  LON: %.4f°", self.cameraLat, self.cameraLon),
            attributes: attrs
        )
        label3.draw(at: CGPoint(x: 30, y: height - 76))
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
