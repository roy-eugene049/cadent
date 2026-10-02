import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static weak var current: AppModel?

    init() {
        Self.current = self
        Log.info("model init")
    }

    func shutdown() {}
}
