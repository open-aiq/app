import AccessorySetupKit
import CoreBluetooth
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AccessorySetupPlugin") {
      AccessorySetupPlugin.register(with: registrar)
    }
  }
}

/// Method channel `org.openaiq/accessory_setup` (lib/ble/discovery.dart).
///
/// iOS 18+: the AccessorySetupKit picker finds Open AIQ monitors (Nordic UART
/// Service, advertised as "AirMonitor-XXXX") in pairing mode. The user
/// authorizes one in a system sheet and its Bluetooth identifier is returned,
/// so FlutterBluePlus can connect without the broad Bluetooth permission prompt.
/// Already-authorized monitors are listed by `listAccessories`.
final class AccessorySetupPlugin: NSObject, FlutterPlugin {
  private static let serviceUUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
  private static let namePrefix = "AirMonitor-"
  private var session: AnyObject?
  private var activated = false
  private var pending: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "org.openaiq/accessory_setup", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AccessorySetupPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 18.0, *) else {
      if call.method == "isSupported" {
        result(false)
      } else {
        result(FlutterError(code: "unsupported", message: "AccessorySetupKit requires iOS 18", details: nil))
      }
      return
    }
    switch call.method {
    case "isSupported":
      result(true)
    case "listAccessories":
      activeSession { session in
        result(session.accessories.compactMap { Self.describe($0) })
      }
    case "showPicker":
      showPicker(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 18.0, *)
  private func activeSession(_ ready: @escaping (ASAccessorySession) -> Void) {
    if let session = session as? ASAccessorySession, activated {
      ready(session)
      return
    }
    let session = ASAccessorySession()
    self.session = session
    session.activate(on: DispatchQueue.main) { [weak self] event in
      if event.eventType == .activated {
        self?.activated = true
        ready(session)
      }
      self?.handle(event: event)
    }
  }

  @available(iOS 18.0, *)
  private func showPicker(result: @escaping FlutterResult) {
    if pending != nil {
      result(FlutterError(code: "busy", message: "The accessory picker is already open", details: nil))
      return
    }
    pending = result
    activeSession { [weak self] session in
      let descriptor = ASDiscoveryDescriptor()
      descriptor.bluetoothServiceUUID = CBUUID(string: Self.serviceUUID)
      descriptor.bluetoothNameSubstring = Self.namePrefix
      let image = UIImage(systemName: "aqi.medium") ?? UIImage(systemName: "sensor") ?? UIImage()
      let item = ASPickerDisplayItem(name: "Open AIQ monitor", productImage: image, descriptor: descriptor)
      session.showPicker(for: [item]) { error in
        if let error {
          self?.finish(FlutterError(code: "picker", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  @available(iOS 18.0, *)
  private func handle(event: ASAccessoryEvent) {
    switch event.eventType {
    case .accessoryAdded, .accessoryChanged:
      if let accessory = event.accessory, let description = Self.describe(accessory) {
        finish(description)
      }
    case .pickerDidDismiss:
      // The added-accessory event may arrive just after the dismissal.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.finish(nil) }
    default:
      break
    }
  }

  @available(iOS 18.0, *)
  private static func describe(_ accessory: ASAccessory) -> [String: String]? {
    guard let identifier = accessory.bluetoothIdentifier else { return nil }
    return ["bluetoothIdentifier": identifier.uuidString, "name": accessory.displayName]
  }

  private func finish(_ value: Any?) {
    guard let result = pending else { return }
    pending = nil
    result(value)
  }
}
