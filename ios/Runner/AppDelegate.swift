import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let replayDirectoryName = "replays"
  private static let replayExtension = "json"

  /// Mirrors `replayFileKeyPattern` in `replay_file_store.dart`. Keys are
  /// logical identifiers; nothing in this file ever accepts a path.
  private static let keyPattern = "^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "hareeg_table/local_storage",
        binaryMessenger: controller.binaryMessenger
      )
      let defaults = UserDefaults.standard

      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(
            code: "io_error",
            message: "The application delegate is gone.",
            details: nil
          ))
          return
        }

        // `listFiles` is the only method with no key. Every other method keeps
        // the original "a storage key is required" guard.
        if call.method == "listFiles" {
          self.handleListFiles(result: result)
          return
        }

        guard
          let arguments = call.arguments as? [String: Any],
          let key = arguments["key"] as? String
        else {
          result(FlutterError(
            code: "invalid_arguments",
            message: "A storage key is required.",
            details: nil
          ))
          return
        }

        switch call.method {
        case "getString":
          result(defaults.string(forKey: key))
        case "setString":
          guard let value = arguments["value"] as? String else {
            result(FlutterError(
              code: "invalid_arguments",
              message: "A string value is required.",
              details: nil
            ))
            return
          }
          defaults.set(value, forKey: key)
          result(nil)
        case "remove":
          defaults.removeObject(forKey: key)
          result(nil)
        case "writeFile":
          guard let value = arguments["value"] as? String else {
            result(FlutterError(
              code: "invalid_arguments",
              message: "A file payload is required.",
              details: nil
            ))
            return
          }
          self.handleWriteFile(key: key, value: value, result: result)
        case "readFile":
          self.handleReadFile(key: key, result: result)
        case "deleteFile":
          self.handleDeleteFile(key: key, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Whether `key` is a usable logical replay key.
  ///
  /// The Dart store validates keys too; this check is deliberately
  /// independent, so a caller that reaches the channel directly still cannot
  /// name a file outside the replay directory. The full-range comparison
  /// matters because `$` in an `NSRegularExpression` also matches before a
  /// trailing newline — without it, `"match-1\n"` would slip through.
  private func isValidReplayKey(_ key: String) -> Bool {
    guard let range = key.range(
      of: AppDelegate.keyPattern,
      options: .regularExpression
    ) else {
      return false
    }

    return range == key.startIndex..<key.endIndex
  }

  /// Returns the replay directory, creating it and re-asserting its
  /// backup exclusion.
  ///
  /// Application Support is backed up by default, so the exclusion flag is what
  /// makes replay payloads no-backup on iOS — the counterpart to Android's
  /// `noBackupFilesDir`. Caches would be purgeable and Documents would be both
  /// user-visible and backed up, so neither is usable here. The flag is
  /// re-asserted on every resolve so a recreated directory cannot silently lose
  /// it.
  private func replayDirectoryURL() throws -> URL {
    let fileManager = FileManager.default
    let base = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )

    var directory = base.appendingPathComponent(
      AppDelegate.replayDirectoryName,
      isDirectory: true
    )

    // `withIntermediateDirectories: true` succeeds when the directory already
    // exists, so this needs no existence check. Asking first would reintroduce
    // a boolean stat whose failure is indistinguishable from absence.
    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)

    return directory
  }

  /// Resolves the file a logical `key` maps to, rejecting anything that would
  /// land outside `directory`.
  ///
  /// The containment comparison is a second, structural guard that does not
  /// depend on the character rule being complete.
  private func replayFileURL(in directory: URL, key: String) -> URL? {
    let candidate = directory
      .appendingPathComponent("\(key).\(AppDelegate.replayExtension)")
      .standardizedFileURL

    guard
      candidate.deletingLastPathComponent().standardizedFileURL.path
        == directory.standardizedFileURL.path
    else {
      return nil
    }

    return candidate
  }

  /// What occupies a replay file name.
  ///
  /// Three outcomes, deliberately not two. A directory can occupy a replay file
  /// name — `listFiles` skips one, and read and delete must skip it too rather
  /// than reading it or recursively removing it.
  private enum ReplayFileKind {
    /// A regular file: a real replay payload.
    case regularFile

    /// Something else — a directory, a symlink to one, a device node. Present,
    /// but never a replay payload.
    case notAReplayPayload

    /// Nothing is there.
    case absent
  }

  /// Classifies what sits at `url`, throwing when the path cannot be inspected.
  ///
  /// The obvious spelling, `fileExists(atPath:isDirectory:)`, returns a `Bool`
  /// and so reports "cannot inspect this path" identically to "nothing is
  /// here". That would let a permissions or metadata failure masquerade as a
  /// missing replay: `readFile` would answer null and `deleteFile` would answer
  /// false, and a caller self-healing a missing replay would discard a payload
  /// that was merely unreadable at that moment.
  ///
  /// Only a genuine no-such-file result maps to `.absent`. Every other
  /// filesystem error propagates to the caller's `catch` and becomes
  /// `io_error`, keeping the absent-versus-broken distinction the Dart API
  /// promises.
  private func replayFileKind(at url: URL) throws -> ReplayFileKind {
    do {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      return values.isRegularFile == true ? .regularFile : .notAReplayPayload
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return .absent
    }
  }

  private func invalidKeyError(_ key: String) -> FlutterError {
    FlutterError(
      code: "invalid_key",
      message: "\"\(key)\" is not a valid replay file key.",
      details: nil
    )
  }

  private func ioError(_ error: Error) -> FlutterError {
    FlutterError(
      code: "io_error",
      message: error.localizedDescription,
      details: nil
    )
  }

  private func handleWriteFile(key: String, value: String, result: FlutterResult) {
    guard isValidReplayKey(key) else {
      result(invalidKeyError(key))
      return
    }

    do {
      let directory = try replayDirectoryURL()
      guard let target = replayFileURL(in: directory, key: key) else {
        result(invalidKeyError(key))
        return
      }

      guard let data = value.data(using: .utf8) else {
        result(FlutterError(
          code: "io_error",
          message: "The replay payload is not encodable as UTF-8.",
          details: nil
        ))
        return
      }

      // `.atomic` stages the payload in a temporary sibling and replaces the
      // target in one step, so the committed payload is never deleted first: a
      // failed write leaves the previous replay readable and takes its own
      // staging file with it.
      try data.write(to: target, options: .atomic)
      result(nil)
    } catch {
      result(ioError(error))
    }
  }

  private func handleReadFile(key: String, result: FlutterResult) {
    guard isValidReplayKey(key) else {
      result(invalidKeyError(key))
      return
    }

    do {
      let directory = try replayDirectoryURL()
      guard let target = replayFileURL(in: directory, key: key) else {
        result(invalidKeyError(key))
        return
      }

      // Absent is a normal answer, not a failure: callers self-heal a missing
      // replay and must be able to tell it from a real error. A directory
      // occupying the name is absent too — it is not a replay payload. A path
      // that cannot be inspected is neither, and throws.
      switch try replayFileKind(at: target) {
      case .absent, .notAReplayPayload:
        result(nil)
        return
      case .regularFile:
        break
      }

      let data = try Data(contentsOf: target)
      guard let contents = String(data: data, encoding: .utf8) else {
        result(FlutterError(
          code: "io_error",
          message: "The stored replay payload is not valid UTF-8.",
          details: nil
        ))
        return
      }

      result(contents)
    } catch {
      result(ioError(error))
    }
  }

  private func handleDeleteFile(key: String, result: FlutterResult) {
    guard isValidReplayKey(key) else {
      result(invalidKeyError(key))
      return
    }

    do {
      let directory = try replayDirectoryURL()
      guard let target = replayFileURL(in: directory, key: key) else {
        result(invalidKeyError(key))
        return
      }

      // Only a regular file is a replay payload. A directory that happens to
      // carry a replay file name reports "did not exist" and is left alone,
      // rather than being recursively removed. A path that cannot be inspected
      // throws instead of being reported as nothing to delete.
      switch try replayFileKind(at: target) {
      case .absent, .notAReplayPayload:
        result(false)
        return
      case .regularFile:
        break
      }

      try FileManager.default.removeItem(at: target)
      result(true)
    } catch {
      result(ioError(error))
    }
  }

  /// Lists logical replay keys.
  ///
  /// An entry is listed only when it is a regular file named `<key>.json` and
  /// `<key>` is a valid logical key. That single rule is what skips
  /// directories, staging siblings, foreign extensions, and files whose name
  /// cannot map back to a key a caller could pass in again.
  private func handleListFiles(result: FlutterResult) {
    do {
      let directory = try replayDirectoryURL()
      let entries = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: []
      )

      // A throwing loop, not `compactMap` with `try?`: a metadata lookup that
      // fails is a backend failure and must surface as `io_error`. Swallowing
      // it would return a short list that looks complete, and a caller cannot
      // tell a partial listing from a real one. Directories and foreign
      // extensions stay intentional skips.
      var keys: [String] = []
      for url in entries {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        guard url.pathExtension == AppDelegate.replayExtension else { continue }

        let key = url.deletingPathExtension().lastPathComponent
        if isValidReplayKey(key) {
          keys.append(key)
        }
      }

      result(keys.sorted())
    } catch {
      result(ioError(error))
    }
  }
}
