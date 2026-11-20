import ActivityKit
import Foundation

/// Actividad en directo (pantalla bloqueada y Dynamic Island).
struct RideAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timerStart: Date   // ahora − tiempo transcurrido: el reloj del sistema cuenta solo
        var paused: Bool
        var elapsed: Double
        var km: Double
        var hr: Int
        var power: Int
    }
}
