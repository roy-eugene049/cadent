import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "com.dukaloco.cadent", category: "app")

    static func info(_ message: String) {
        app.info("\(message, privacy: .public)")
        NSLog("Cadent: %@", message)
    }

    static func error(_ message: String) {
        app.error("\(message, privacy: .public)")
        NSLog("Cadent error: %@", message)
    }
}
