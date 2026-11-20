import SwiftUI
import HealthKit
import ActivityKit
import UserNotifications

struct Sample: Identifiable, Codable {
    var t, cad, pow, hr, spd: Double
    var id: Double { t }
}

/// Parcial de 1 km.
struct Split: Identifiable, Codable {
    var km: Int
    var time, avgPow, avgHR, avgCad: Double
    var id: Int { km }
}

struct Record: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let duration: Double
    let avgPow, maxPow, avgCad, avgHR, maxHR, kcal, km: Double
    let inHealth: Bool
    let samples: [Sample]
    var effort: Int? = nil       // 1–10, opcional
    var splits: [Split]? = nil
}

enum Choice { case health, recordOnly, discard }

func avg(_ xs: [Double]) -> Double {
    let v = xs.filter { $0 > 0 }
    return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
}

/// Escala de esfuerzo de Apple (1–10).
func effortLabel(_ e: Int) -> String {
    switch e {
    case ...3: "Fácil"
    case 4...6: "Moderado"
    case 7...8: "Difícil"
    default: "Máximo"
    }
}

@Observable
final class PhoneModel: NSObject, HKWorkoutSessionDelegate {
    let sensor = BikeSensor()
    let link = Link()
    var running = false
    var paused = false
    var history: [Sample] = []
    var splits: [Split] = []
    var records: [Record] = []
    private(set) var startDate: Date?
    private var segStart: Date?
    private var accum = 0.0
    private let store = HKHealthStore()
    private let file = URL.documentsDirectory.appending(path: "registros.json")
    private var lastSample = Date.distantPast
    private var lastLive = Date.distantPast
    private var lastSplitT = 0.0
    private var lastData = Date.distantPast   // última vez que se pedaleaba (cadencia > 0)
    private var autoPaused = false             // pausa por falta de señal (se reanuda sola)
    private var lastVoiceMark = 0
    private var heartbeat: Timer?   // manda el estado al reloj aunque la bici aún no emita
    private var activity: Activity<RideAttributes>?
    private let coach = Coach()

    override init() {
        super.init()
        records = (try? JSONDecoder().decode([Record].self, from: Data(contentsOf: file))) ?? []
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        sensor.onData = { [weak self] in
            guard let self else { return }
            guard sensor.cadence > 0 else { tick(); return }   // la bici sigue mandando datos con cadencia 0 al parar
            lastData = Date()
            if autoPaused, paused { togglePause() }   // vuelve a pedalear: reanuda
            tick()
        }
        link.onMessage = { [weak self] m in
            guard let self else { return }
            if let l = m["lvl"] as? Double { self.sensor.level = min(10, max(1, Int(l))) }
            if let p = m["paused"] as? Double { self.setPaused(p == 1) }
            // Terminado en el reloj: "Guardar" va a Salud y a registros; "Descartar" no deja nada.
            if m["cmd"] as? String == "ended", self.running {
                let save = (m["save"] as? NSNumber)?.boolValue ?? true
                self.close(inHealth: save, keep: save, effort: (m["effort"] as? NSNumber)?.intValue)
            }
        }
        // El reloj empezó el entreno: iOS lanza esta app en segundo plano y llama aquí.
        store.workoutSessionMirroringStartHandler = { [weak self] s in
            guard let self else { return }
            s.delegate = self   // debe fijarse aquí mismo, antes de que el handler termine
            DispatchQueue.main.async {
                self.link.session = s
                self.begin()
            }
        }
    }

    func elapsed(at d: Date) -> Double { accum + (segStart.map { d.timeIntervalSince($0) } ?? 0) }
    var km: Double { history.map(\.spd).reduce(0, +) / 3600 }

    // MARK: Ajustes (los mismos que @AppStorage en la pantalla de ajustes)

    private var voiceOn: Bool { UserDefaults.standard.object(forKey: "voice") as? Bool ?? true }
    private var voiceKm: Bool { UserDefaults.standard.object(forKey: "voiceKm") as? Bool ?? true }
    private var voiceMinutes: Int { UserDefaults.standard.object(forKey: "voiceMinutes") as? Int ?? 5 }

    // MARK: Ciclo del entrenamiento

    private func begin() {
        guard !running else { return }
        running = true; paused = true   // el reloj reanuda cuando la bici esté conectada
        startDate = Date(); segStart = nil; accum = 0
        history = []; splits = []; lastSplitT = 0; lastVoiceMark = 0
        sensor.start()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }
        startLive()
        let c = UNMutableNotificationContent()
        c.title = "Entrenamiento en marcha"; c.body = "Toca para ver tiempo, gráficas y parciales."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "start", content: c, trigger: nil))
    }

    /// La app vuelve a primer plano: reintenta lo que en segundo plano no se puede.
    func appActive() {
        guard running else { return }
        sensor.kick()
        if activity == nil { startLive() }
    }

    private func tick() {   // con cada dato de la bici y cada segundo
        link.send(["st": sensor.status, "cad": Double(sensor.cadence),
                   "pow": Double(sensor.power), "spd": sensor.speed, "lvl": Double(sensor.level)])
        let now = Date()
        // Sin pedalear (o sin datos) durante 5 s (desde la última lectura o desde que se reanudó): pausa sola.
        if running, !paused, now.timeIntervalSince(max(lastData, segStart ?? now)) > 5 {
            togglePause(); autoPaused = true
            return
        }
        guard running, !paused, now.timeIntervalSince(lastSample) >= 1 else { return }
        lastSample = now
        let t = elapsed(at: now)
        history.append(Sample(t: t, cad: Double(sensor.cadence), pow: Double(sensor.power),
                              hr: link.num("hr"), spd: sensor.speed))
        checkSplit(t)
        checkVoiceTime(t)
        if now.timeIntervalSince(lastLive) >= 5 { lastLive = now; updateLive() }
    }

    private func checkSplit(_ t: Double) {
        guard Int(km) > splits.count else { return }
        let seg = history.filter { $0.t > lastSplitT }
        let s = Split(km: splits.count + 1, time: t - lastSplitT, avgPow: avg(seg.map(\.pow)),
                      avgHR: avg(seg.map(\.hr)), avgCad: avg(seg.map(\.cad)))
        withAnimation(.spring) { splits.append(s) }
        lastSplitT = t
        link.send(["lap": Double(s.km), "lapTime": s.time])
        if voiceOn, voiceKm {
            coach.say("Kilómetro \(s.km). Parcial \(Coach.spoken(s.time)). " +
                      "Potencia media \(Int(s.avgPow)) vatios. Pulso \(Int(link.num("hr"))).")
        }
    }

    private func checkVoiceTime(_ t: Double) {
        let every = voiceMinutes * 60
        guard voiceOn, every > 0, Int(t) / every > lastVoiceMark else { return }
        lastVoiceMark = Int(t) / every
        coach.say("\(Int(t) / 60) minutos. \(String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")) kilómetros. " +
                  "Pulso \(Int(link.num("hr"))). Potencia \(sensor.power) vatios.")
    }

    private func setPaused(_ p: Bool) {
        guard running, p != paused else { return }
        autoPaused = false
        let now = Date()
        if p { accum = elapsed(at: now); segStart = nil } else { segStart = now }
        withAnimation(.snappy) { paused = p }
        updateLive()
    }

    func togglePause() {
        let p = !paused
        setPaused(p)
        link.send(["cmd": p ? "pause" : "resume"])
        if voiceOn { coach.say(p ? "Pausa" : "Reanudado") }
    }

    /// Finaliza desde el iPhone: guarda en Salud, solo en registros, o descarta. El esfuerzo es opcional.
    func finish(_ c: Choice, effort: Int?) {
        guard running else { return }
        var cmd: [String: Any] = ["cmd": "end", "save": c == .health]
        if let effort { cmd["effort"] = effort }
        link.send(cmd)
        close(inHealth: c == .health, keep: c != .discard, effort: effort)
    }

    private func close(inHealth: Bool, keep: Bool, effort: Int?) {
        if keep {
            var r = makeRecord(inHealth: inHealth)
            r.effort = effort; r.splits = splits
            withAnimation { records.insert(r, at: 0) }
            saveRecords()
        }
        heartbeat?.invalidate(); heartbeat = nil
        sensor.stop()
        endLive()
        withAnimation(.smooth) { running = false; paused = false }
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func makeRecord(inHealth: Bool) -> Record {
        let hr = history.map(\.hr).filter { $0 > 0 }
        return Record(date: startDate ?? .now, duration: elapsed(at: .now),
                      avgPow: avg(history.map(\.pow)), maxPow: history.map(\.pow).max() ?? 0,
                      avgCad: avg(history.map(\.cad)), avgHR: avg(hr), maxHR: hr.max() ?? 0,
                      kcal: link.num("kcal"), km: km, inHealth: inHealth, samples: history)
    }

    func deleteRecords(at o: IndexSet) { records.remove(atOffsets: o); saveRecords() }
    private func saveRecords() { try? JSONEncoder().encode(records).write(to: file, options: .completeFileProtection) }

    // MARK: Actividad en directo (solo se puede crear con la app en primer plano)

    private func liveState() -> RideAttributes.ContentState {
        let now = Date(), e = elapsed(at: now)
        return .init(timerStart: now.addingTimeInterval(-e), paused: paused, elapsed: e,
                     km: km, hr: Int(link.num("hr")), power: sensor.power)
    }

    private func startLive() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do { activity = try Activity.request(attributes: RideAttributes(), content: .init(state: liveState(), staleDate: nil)) }
        catch { print("Live Activity:", error) }   // en segundo plano falla; se reintenta al abrir la app
    }

    private func updateLive() {
        guard let a = activity else { return }
        let s = liveState()
        Task { await a.update(.init(state: s, staleDate: nil)) }
    }

    private func endLive() {
        guard let a = activity else { return }
        activity = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: Sesión espejo del reloj

    // Si el entreno termina en el reloj sin aviso previo, ya se guardó allí en Salud.
    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {
        guard to == .ended else { return }
        DispatchQueue.main.async { if self.running { self.close(inHealth: true, keep: true, effort: nil) } }
    }
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {}
    func workoutSession(_ s: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        data.forEach(link.receive)
    }
}
