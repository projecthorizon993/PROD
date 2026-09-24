import Foundation
import os.log

enum AppLogger {
    static let subsystem = "com.camerapp"
    static let proCamera = OSLog(subsystem: subsystem, category: "ProCamera")
    static let ane = OSLog(subsystem: subsystem, category: "ANE")
    static let lowLight = OSLog(subsystem: subsystem, category: "LowLight")
    static let lens = OSLog(subsystem: subsystem, category: "Lens")
    static let grading = OSLog(subsystem: subsystem, category: "Grading")
    static let bracket = OSLog(subsystem: subsystem, category: "Bracket")
    static let zoom = OSLog(subsystem: subsystem, category: "Zoom")
    static let bridge = OSLog(subsystem: subsystem, category: "Bridge")

    static func log(_ message: String, category: String = "ProCamera", type: OSLogType = .info, file: String = #file, line: Int = #line, function: String = #function) {
        let log: OSLog
        switch category {
        case "ANE": log = ane
        case "LowLight": log = lowLight
        case "Lens": log = lens
        case "Grading": log = grading
        case "Bracket": log = bracket
        case "Zoom": log = zoom
        case "Bridge": log = bridge
        default: log = proCamera
        }
        let fileName = (file as NSString).lastPathComponent
        let formatted = "[\(fileName):\(line) \(function)] \(message)"
        os_log("%{public}@", log: log, type: type, formatted)
        NSLog("[\(subsystem):\(category)] \(formatted)")
        FileLogger.shared.append("[\(category)] \(formatted)")
    }

    static func info(_ message: String, category: String = "ProCamera", file: String = #file, line: Int = #line, function: String = #function) {
        log(message, category: category, type: .info, file: file, line: line, function: function)
    }

    static func debug(_ message: String, category: String = "ProCamera", file: String = #file, line: Int = #line, function: String = #function) {
        log(message, category: category, type: .debug, file: file, line: line, function: function)
    }

    static func error(_ message: String, category: String = "ProCamera", file: String = #file, line: Int = #line, function: String = #function) {
        log(message, category: category, type: .error, file: file, line: line, function: function)
    }

    static func fault(_ message: String, category: String = "ProCamera", file: String = #file, line: Int = #line, function: String = #function) {
        log(message, category: category, type: .fault, file: file, line: line, function: function)
    }
}

final class FileLogger {
    static let shared = FileLogger()
    private let queue = DispatchQueue(label: "com.camerapp.filelogger", qos: .utility)
    private let maxBytes: UInt64 = 2 * 1024 * 1024
    private let fileURL: URL?

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("procamera.log")
    }

    func append(_ line: String) {
        queue.async {
            guard let url = self.fileURL else { return }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let entry = "\(timestamp) \(line)\n"
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    if let data = entry.data(using: .utf8) { handle.write(data) }
                    handle.closeFile()
                    self.rotateIfNeeded(url: url)
                }
            } else {
                try? entry.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    func read() -> String {
        queue.sync {
            guard let url = fileURL, let data = try? Data(contentsOf: url) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    func clear() {
        queue.async {
            guard let url = self.fileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func filePath() -> String? {
        fileURL?.path
    }

    private func rotateIfNeeded(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              size > maxBytes else { return }
        if let handle = try? FileHandle(forReadingFrom: url) {
            handle.seek(toFileOffset: size - maxBytes / 2)
            let data = handle.readDataToEndOfFile()
            handle.closeFile()
            try? data.write(to: url)
        }
    }
}
