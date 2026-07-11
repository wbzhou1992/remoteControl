import Cocoa
import CoreGraphics
import FlutterMacOS

final class InputInjectorHandler: NSObject, FlutterPlugin {
  private static var captureFrame: CGRect?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.remotecontrol/input",
      binaryMessenger: registrar.messenger
    )
    let instance = InputInjectorHandler()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "inject":
      guard let args = call.arguments as? [String: Any],
            let type = args["type"] as? String,
            let x = args["x"] as? Double,
            let y = args["y"] as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing input args", details: nil))
        return
      }
      let button = args["button"] as? Int ?? 0
      let deltaY = args["deltaY"] as? Double ?? 0
      inject(type: type, normX: x, normY: y, button: button, deltaY: deltaY)
      result(nil)

    case "setCaptureSource":
      let args = call.arguments as? [String: Any]
      let sourceId = args?["sourceId"] as? String
      let sourceName = args?["sourceName"] as? String
      let sourceType = args?["sourceType"] as? String
      Self.captureFrame = Self.frameForSource(
        sourceId: sourceId,
        sourceName: sourceName,
        sourceType: sourceType
      )
      if let frame = Self.captureFrame {
        result([
          "x": frame.origin.x,
          "y": frame.origin.y,
          "width": frame.width,
          "height": frame.height,
        ])
      } else {
        result(nil)
      }

    case "getScreenSize":
      if let frame = Self.captureFrame ?? Self.quartzFrame(for: NSScreen.main) {
        result(["width": frame.width, "height": frame.height])
      } else {
        result(["width": 1920.0, "height": 1080.0])
      }

    case "decodeThumbnail":
      if let data = Self.thumbnailData(from: call.arguments) {
        result(Self.decodeThumbnailToPng(data))
      } else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected thumbnail bytes", details: nil))
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// CGEvent uses Quartz coordinates (origin top-left). NSScreen.frame uses Cocoa (origin bottom-left).
  private static func thumbnailData(from arguments: Any?) -> Data? {
    if let typed = arguments as? FlutterStandardTypedData {
      return typed.data
    }
    if let list = arguments as? [UInt8] {
      return Data(list)
    }
    if let list = arguments as? [NSNumber] {
      return Data(list.map { $0.uint8Value })
    }
    return nil
  }

  private static func decodeThumbnailToPng(_ data: Data) -> FlutterStandardTypedData? {
    guard let image = NSImage(data: data),
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
      return nil
    }
    return FlutterStandardTypedData(bytes: png)
  }

  private static func quartzFrame(for screen: NSScreen?) -> CGRect? {
    guard let screen else { return nil }
    let cocoa = screen.frame
    let maxY = NSScreen.screens.map { $0.frame.maxY }.max() ?? cocoa.maxY
    return CGRect(
      x: cocoa.origin.x,
      y: maxY - cocoa.maxY,
      width: cocoa.width,
      height: cocoa.height
    )
  }

  private static func parseNumericId(_ sourceId: String) -> UInt32? {
    if let id = UInt32(sourceId) { return id }
    if let colon = sourceId.lastIndex(of: ":") {
      let suffix = String(sourceId[sourceId.index(after: colon)...])
      return UInt32(suffix)
    }
    return nil
  }

  private static func frameForWindowId(_ windowId: CGWindowID) -> CGRect? {
    guard let infoList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowId) as? [[String: Any]],
          let info = infoList.first,
          let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
          let x = boundsDict["X"] as? CGFloat,
          let y = boundsDict["Y"] as? CGFloat,
          let w = boundsDict["Width"] as? CGFloat,
          let h = boundsDict["Height"] as? CGFloat else {
      return nil
    }
    return CGRect(x: x, y: y, width: w, height: h)
  }

  private static func frameForSource(
    sourceId: String?,
    sourceName: String?,
    sourceType: String?
  ) -> CGRect? {
    if sourceType == "window", let sourceId, let windowId = parseNumericId(sourceId) {
      if let frame = frameForWindowId(CGWindowID(windowId)) {
        return frame
      }
    }

    if let sourceId, !sourceId.isEmpty {
      if let numericId = parseNumericId(sourceId) {
        let displayId = CGDirectDisplayID(numericId)
        if CGDisplayIsOnline(displayId) != 0 {
          let bounds = CGDisplayBounds(displayId)
          if bounds.width > 0 && bounds.height > 0 {
            return bounds
          }
        }
        if let frame = frameForWindowId(CGWindowID(numericId)) {
          return frame
        }
      }

      for screen in NSScreen.screens {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
          continue
        }
        let displayId = number.uint32Value
        if sourceId == String(displayId)
          || sourceId == String(number.intValue)
          || sourceId.hasSuffix(":\(displayId)") {
          return CGDisplayBounds(CGDirectDisplayID(displayId))
        }
      }

      if let sourceName, !sourceName.isEmpty {
        for screen in NSScreen.screens {
          let name = screen.localizedName
          if name == sourceName || sourceName.contains(name) || name.contains(sourceName) {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
              return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            }
            return quartzFrame(for: screen)
          }
        }
      }

      if let sourceName, !sourceName.isEmpty {
        for screen in NSScreen.screens where sourceId.contains(screen.localizedName) {
          if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
          }
          return quartzFrame(for: screen)
        }
      }
    }

    if let sourceName, !sourceName.isEmpty {
      if let match = sourceName.range(of: #"Screen\s+(\d+)"#, options: .regularExpression) {
        let indexStr = String(sourceName[match]).replacingOccurrences(of: "Screen", with: "").trimmingCharacters(in: .whitespaces)
        if let index = Int(indexStr), index > 0, index <= NSScreen.screens.count {
          let screen = NSScreen.screens[index - 1]
          if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
          }
          return quartzFrame(for: screen)
        }
      }
    }

    return quartzFrame(for: NSScreen.main)
  }

  private func screenPoint(normX: Double, normY: Double) -> CGPoint {
    let frame = Self.captureFrame
      ?? Self.quartzFrame(for: NSScreen.main)
      ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    return CGPoint(
      x: frame.origin.x + normX * frame.width,
      y: frame.origin.y + normY * frame.height
    )
  }

  private func postMouseMove(to point: CGPoint, source: CGEventSource) {
    let event = CGEvent(
      mouseEventSource: source,
      mouseType: .mouseMoved,
      mouseCursorPosition: point,
      mouseButton: .left
    )
    event?.post(tap: .cghidEventTap)
  }

  private func inject(type: String, normX: Double, normY: Double, button: Int, deltaY: Double) {
    let point = screenPoint(normX: normX, normY: normY)
    guard let source = CGEventSource(stateID: .hidSystemState) else { return }

    switch type {
    case "mousemove":
      postMouseMove(to: point, source: source)

    case "mousedown":
      postMouseMove(to: point, source: source)
      let (mouseType, mouseButton) = mouseDownType(for: button)
      let event = CGEvent(
        mouseEventSource: source,
        mouseType: mouseType,
        mouseCursorPosition: point,
        mouseButton: mouseButton
      )
      event?.post(tap: .cghidEventTap)

    case "mouseup":
      let (mouseType, mouseButton) = mouseUpType(for: button)
      let event = CGEvent(
        mouseEventSource: source,
        mouseType: mouseType,
        mouseCursorPosition: point,
        mouseButton: mouseButton
      )
      event?.post(tap: .cghidEventTap)

    case "click":
      postMouseMove(to: point, source: source)
      let (downType, upType, mouseButton) = clickTypes(for: button)
      let down = CGEvent(
        mouseEventSource: source,
        mouseType: downType,
        mouseCursorPosition: point,
        mouseButton: mouseButton
      )
      down?.post(tap: .cghidEventTap)
      let up = CGEvent(
        mouseEventSource: source,
        mouseType: upType,
        mouseCursorPosition: point,
        mouseButton: mouseButton
      )
      up?.post(tap: .cghidEventTap)

    case "scroll":
      postMouseMove(to: point, source: source)
      let lines = Int32((-deltaY / 10).rounded().clamped(to: -10...10))
      guard lines != 0 else { return }
      let scroll = CGEvent(
        scrollWheelEvent2Source: source,
        units: .line,
        wheelCount: 1,
        wheel1: lines,
        wheel2: 0,
        wheel3: 0
      )
      scroll?.location = point
      scroll?.post(tap: .cghidEventTap)

    default:
      break
    }
  }

  private func mouseDownType(for button: Int) -> (CGEventType, CGMouseButton) {
    switch button {
    case 2: return (.rightMouseDown, .right)
    case 1: return (.otherMouseDown, .center)
    default: return (.leftMouseDown, .left)
    }
  }

  private func mouseUpType(for button: Int) -> (CGEventType, CGMouseButton) {
    switch button {
    case 2: return (.rightMouseUp, .right)
    case 1: return (.otherMouseUp, .center)
    default: return (.leftMouseUp, .left)
    }
  }

  private func clickTypes(for button: Int) -> (CGEventType, CGEventType, CGMouseButton) {
    switch button {
    case 2: return (.rightMouseDown, .rightMouseUp, .right)
    case 1: return (.otherMouseDown, .otherMouseUp, .center)
    default: return (.leftMouseDown, .leftMouseUp, .left)
    }
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
