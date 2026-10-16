import Flutter
import UIKit

import AdServices

/// Flutter entry point on iOS.
///
/// `read` returns the AdServices attribution token. Fetching it
/// needs no App Tracking Transparency prompt. Every failure is sent back as
/// data (`status: unavailable`) — never as a FlutterError.
public final class ImajiInstallAttributionPlugin: NSObject, FlutterPlugin {
  private static let channelName = "io.github.saimskywalker/imaji_install_attribution"

  /// `attributionToken()` is synchronous and may take a moment; it never runs
  /// on the main thread.
  private let worker = DispatchQueue(label: "imaji-install-attribution", qos: .utility)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ImajiInstallAttributionPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "read":
      let arguments = call.arguments as? [String: Any]
      let timeoutMs = (arguments?["timeoutMs"] as? NSNumber)?.intValue ?? 10_000
      read(timeoutMs: max(1, timeoutMs), reply: ReplyOnce(result))
    case "installSource":
      // iOS has no installer package to report.
      result(nil)
    case "installFacts":
      // No referrer to protect on iOS: `treatUpgradesAsHandled` is a no-op.
      result(nil)
    case "isHandled":
      onWorker(result) { HandledMarker.isHandled() }
    case "markHandled":
      onWorker(result) { HandledMarker.markHandled() }
    case "clearHandled":
      onWorker(result) { HandledMarker.clear() }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func read(timeoutMs: Int, reply: ReplyOnce) {
    #if targetEnvironment(simulator)
      reply.send(
        Self.unavailable(
          "notSupported", "AdServices does not issue attribution tokens on the simulator."))
    #else
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
        reply.send(
          Self.unavailable("timeout", "No attribution token within \(timeoutMs)ms."))
      }
      worker.async {
        let outcome: [String: Any]
        do {
          let token = try AAAttribution.attributionToken()
          outcome = ["status": "token", "token": token]
        } catch {
          outcome = Self.map(error)
        }
        DispatchQueue.main.async { reply.send(outcome) }
      }
    #endif
  }

  private static func map(_ error: Error) -> [String: Any] {
    guard let attributionError = error as? AAAttributionError else {
      return unavailable("internalError", error.localizedDescription)
    }
    switch attributionError.code {
    case .networkError:
      return unavailable("networkError", attributionError.localizedDescription)
    case .platformNotSupported:
      return unavailable("notSupported", attributionError.localizedDescription)
    default:
      return unavailable("internalError", attributionError.localizedDescription)
    }
  }

  private static func unavailable(_ reason: String, _ message: String) -> [String: Any] {
    ["status": "unavailable", "reason": reason, "message": message]
  }

  private func onWorker(_ result: @escaping FlutterResult, _ work: @escaping () -> Bool) {
    worker.async {
      let value = work()
      DispatchQueue.main.async { result(value) }
    }
  }
}

/// Completes a FlutterResult at most once. Only touched on the main thread.
private final class ReplyOnce {
  private var result: FlutterResult?

  init(_ result: @escaping FlutterResult) {
    self.result = result
  }

  func send(_ value: Any?) {
    guard let pending = result else { return }
    result = nil
    pending(value)
  }
}

/// The consume-once marker: one tiny file in Application Support, excluded
/// from iCloud / device backups so a reinstall starts unhandled.
private enum HandledMarker {
  private static var url: URL? {
    guard
      let directory = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else { return nil }
    return directory.appendingPathComponent("imaji_install_attribution.handled")
  }

  static func isHandled() -> Bool {
    guard let url = url else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  static func markHandled() -> Bool {
    guard var url = url else { return false }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data("1".utf8).write(to: url, options: .atomic)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try url.setResourceValues(values)
      return true
    } catch {
      return FileManager.default.fileExists(atPath: url.path)
    }
  }

  static func clear() -> Bool {
    guard let url = url else { return false }
    do {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      return true
    } catch {
      return false
    }
  }
}
