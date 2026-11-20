import HealthKit
import Observation
import WatchKit

@Observable
final class WorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    var heartRate = 0.0
    var calories = 0.0
    var running = false
    var paused = false
    var awaitingBike = false   // en pausa hasta que iPhone y sensor estén conectados
    var stateText = ""         // estado real de la sesión, visible para depurar
    var today = (n: 0, secs: 0.0, km: 0.0, kcal: 0.0)   // resumen de hoy, desde Salud
    var lap: (km: Int, time: Double)?   // último parcial, se muestra unos segundos

    static let shared = WorkoutManager()
    let link = Link()
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var saveOnEnd = true
    private var effortOnEnd: Int?

    override init() {
        super.init()
        link.onMessage = { [weak self] m in
            guard let self else { return }
            if m["pow"] != nil { self.addBikeSamples(m) }
            if let km = m["lap"] as? Double { self.showLap(Int(km), m["lapTime"] as? Double ?? 0) }
            guard self.awaitingBike, m["st"] as? String == "Conectado" else { return }
            self.awaitingBike = false
            self.resume()
        }
    }

    private func showLap(_ km: Int, _ t: Double) {
        WKInterfaceDevice.current().play(.notification)
        lap = (km, t)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.lap?.km == km { self?.lap = nil }
        }
    }

    /// Lo que se guarda en Salud: el reloj aporta pulso y kcal; la bici, potencia, cadencia, velocidad y distancia.
    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
        HKQuantityType(.cyclingPower), HKQuantityType(.cyclingCadence), HKQuantityType(.cyclingSpeed),
        HKQuantityType(.distanceCycling), HKQuantityType(.workoutEffortScore),
    ]
    private var lastAdd = Date.distantPast

    /// Añade los datos de la bici al entrenamiento cada 5 s (aparecen en Fitness y Salud).
    private func addBikeSamples(_ m: [String: Any]) {
        guard running, !paused, !awaitingBike, let b = builder else { return }
        let now = Date(), dt = now.timeIntervalSince(lastAdd)
        guard dt >= 5 else { return }
        let start = lastAdd
        lastAdd = now
        guard dt < 30 else { return }   // tras una pausa o al empezar: solo reinicia el intervalo
        let mps = (m["spd"] as? Double ?? 0) / 3.6
        func q(_ id: HKQuantityTypeIdentifier, _ u: HKUnit, _ v: Double) -> HKQuantitySample {
            HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: u, doubleValue: v), start: start, end: now)
        }
        b.add([
            q(.cyclingPower, .watt(), m["pow"] as? Double ?? 0),
            q(.cyclingCadence, .count().unitDivided(by: .minute()), m["cad"] as? Double ?? 0),
            q(.cyclingSpeed, .meter().unitDivided(by: .second()), mps),
            q(.distanceCycling, .meter(), mps * dt),
        ]) { ok, error in if !ok { print("WATCH add samples:", error as Any) } }
    }

    /// Entrenos de bici de hoy guardados en Salud (los "solo en registros" del iPhone no cuentan).
    func loadToday() async {
        let read: Set<HKObjectType> = [.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceCycling)]
        try? await store.requestAuthorization(toShare: Self.shareTypes, read: read)
        let pred = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: .now), end: nil)
        let all: [HKWorkout] = await withCheckedContinuation { c in
            store.execute(HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: HKObjectQueryNoLimit,
                                        sortDescriptors: nil) { _, r, _ in c.resume(returning: r as? [HKWorkout] ?? []) })
        }
        let ws = all.filter { $0.workoutActivityType == .cycling }
        func sum(_ id: HKQuantityTypeIdentifier, _ u: HKUnit) -> Double {
            ws.compactMap { $0.statistics(for: HKQuantityType(id))?.sumQuantity()?.doubleValue(for: u) }.reduce(0, +)
        }
        today = (ws.count, ws.map(\.duration).reduce(0, +), sum(.distanceCycling, .meterUnit(with: .kilo)),
                 sum(.activeEnergyBurned, .kilocalorie()))
    }

    func start() async {
        guard !running else { return }
        running = true; awaitingBike = true   // evita doble arranque
        saveOnEnd = true; heartRate = 0; calories = 0; link.remote = [:]
        let types: Set = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do { try await store.requestAuthorization(toShare: Self.shareTypes, read: types) }
        catch { print("WATCH auth error:", error) }
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .cycling
        cfg.locationType = .indoor
        let s: HKWorkoutSession
        do { s = try HKWorkoutSession(healthStore: store, configuration: cfg) }
        catch { print("WATCH sesión:", error); running = false; awaitingBike = false; return }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
        s.delegate = self; b.delegate = self
        session = s; builder = b
        link.session = s
        let now = Date()
        s.startActivity(with: now)
        try? await b.beginCollection(at: now)
        do { try await s.startMirroringToCompanionDevice() }   // lanza la app del iPhone
        catch { print("WATCH espejo error:", error) }
    }

    // Si la sesión ya terminó, los botones solo devuelven la pantalla a "Empezar".
    func pause() { guard live() else { return }; session?.pause() }
    func resume() { guard live() else { return }; session?.resume() }
    /// `effort`: 1–10, opcional. `notify`: avisa al iPhone (no hace falta si la orden vino de él).
    func end(save: Bool, effort: Int? = nil, notify: Bool = true) {
        saveOnEnd = save; effortOnEnd = effort
        guard live() else { return }
        if notify {
            var m: [String: Any] = ["cmd": "ended", "save": save]
            if let effort { m["effort"] = effort }
            link.send(m)
        }
        session?.end()
    }

    func elapsed(at d: Date) -> TimeInterval { builder?.elapsedTime(at: d) ?? 0 }

    private func live() -> Bool {
        guard let s = session, s.state != .ended else { markEnded(); return false }
        return true
    }

    private func markEnded() {
        DispatchQueue.main.async { self.running = false; self.paused = false; self.awaitingBike = false }
    }

    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { self.stateText = "sesión: \(Self.name(to))" }
        switch to {
        case .paused, .running:
            DispatchQueue.main.async { self.paused = (to == .paused) }
            link.send(["paused": to == .paused ? 1.0 : 0.0])
            if to == .running, awaitingBike { DispatchQueue.main.async { self.pause() } }
            if !awaitingBike, from == .running || from == .paused {
                WKInterfaceDevice.current().play(to == .paused ? .stop : .start)
            }
        case .ended:
            markEnded()   // la pantalla se actualiza ya, sin esperar a guardar en Salud
            WKInterfaceDevice.current().play(.success)
            let save = saveOnEnd, effort = effortOnEnd, b = builder, store = store
            Task {
                try? await b?.endCollection(at: date)
                guard save else { b?.discardWorkout(); return }
                guard let w = try? await b?.finishWorkout(), let effort else { return }
                // Esfuerzo: aparece en Fitness y Salud junto al entrenamiento.
                let e = HKQuantitySample(type: HKQuantityType(.workoutEffortScore),
                                         quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: Double(effort)),
                                         start: w.startDate, end: w.endDate)
                do { try await store.relateWorkoutEffortSample(e, with: w, activity: nil) }
                catch { print("WATCH esfuerzo:", error) }
            }
        default: break
        }
    }
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.stateText = "error: \(error.localizedDescription)" }
    }

    private static func name(_ s: HKWorkoutSessionState) -> String {
        switch s {
        case .running: "en marcha"
        case .paused: "pausada"
        case .ended: "terminada"
        case .prepared: "preparada"
        case .stopped: "detenida"
        default: "sin empezar"
        }
    }

    /// Órdenes del iPhone: pause, resume, end (con save: true/false).
    func workoutSession(_ s: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for d in data {
            guard let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            switch m["cmd"] as? String {
            case "pause": DispatchQueue.main.async { self.pause() }
            case "resume": DispatchQueue.main.async { self.resume() }
            case "end": let save = (m["save"] as? NSNumber)?.boolValue ?? true
                        let effort = (m["effort"] as? NSNumber)?.intValue
                        DispatchQueue.main.async { self.end(save: save, effort: effort, notify: false) }
            default: link.receive(d)
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        for t in types {
            guard let q = t as? HKQuantityType, let st = b.statistics(for: q) else { continue }
            if q == HKQuantityType(.heartRate) {
                heartRate = st.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
            } else if q == HKQuantityType(.activeEnergyBurned) {
                calories = st.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            }
        }
        link.send(["hr": heartRate, "kcal": calories])
    }
}
