import HealthKit
import Observation

/// Canal iPhone <-> reloj por la sesión de entrenamiento espejada (HealthKit).
@Observable
final class Link {
    var remote: [String: Any] = [:]
    var session: HKWorkoutSession?
    var onMessage: (([String: Any]) -> Void)?

    func send(_ d: [String: Any]) {
        guard let s = session, let data = try? JSONSerialization.data(withJSONObject: d) else { return }
        Task { try? await s.sendToRemoteWorkoutSession(data: data) }
    }

    func receive(_ data: Data) {
        guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        DispatchQueue.main.async { self.remote.merge(d) { $1 }; self.onMessage?(d) }
    }

    func num(_ k: String) -> Double { remote[k] as? Double ?? 0 }
}
