import AVFoundation

/// Avisos por voz en los auriculares: baja la música mientras habla y la devuelve al terminar.
final class Coach: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String) {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? s.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "es-ES")
        synth.speak(u)
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        guard !s.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// "2 minutos 41 segundos"
    static func spoken(_ t: Double) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return m > 0 ? "\(m) minuto\(m == 1 ? "" : "s") \(s) segundos" : "\(s) segundos"
    }
}
