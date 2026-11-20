import Foundation

/// 05:32, o 1:05:32 si pasa de una hora.
func mmss(_ s: Double) -> String {
    let t = max(0, Int(s))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                     : String(format: "%02d:%02d", t / 60, t % 60)
}
