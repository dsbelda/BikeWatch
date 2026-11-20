import CoreBluetooth
import Observation

/// Conecta con el primer sensor que anuncie FTMS (0x1826), Cycling Power (0x1818) o
/// Cycling Speed and Cadence (0x1816) y cuyo nombre empiece por el filtro de Ajustes (vacío = cualquiera).
/// Lee Indoor Bike Data (0x2AD2), Cycling Power Measurement (0x2A63) o CSC Measurement (0x2A5B).
@Observable
final class BikeSensor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var status = "Parado"
    var cadence = 0      // rpm
    var power = 0        // W
    var speed = 0.0      // km/h
    /// Nivel del tornillo de resistencia (1–10): la bici no lo mide, se ajusta a mano en pantalla.
    var level = UserDefaults.standard.object(forKey: "bikeLevel") as? Int ?? 4 {
        didSet { UserDefaults.standard.set(level, forKey: "bikeLevel") }
    }
    static let wattsPerRpmLevel = 0.3   // ponytail: calibración aproximada W = rpm × 0.3 × nivel; ajustar con un medidor real
    var onData: (() -> Void)?

    var connected: Bool { status == "Conectado" }
    var deviceName = ""

    // Ajustes (mismas claves que @AppStorage en SettingsView)
    static let prefixKey = "sensorPrefix", estimateKey = "estimatePower"
    private var namePrefix: String { (UserDefaults.standard.string(forKey: Self.prefixKey) ?? "").lowercased() }
    /// Sensores sin potencia (cadencia) o bicis que la estiman mal: W = rpm × nivel.
    private var estimatePower: Bool { UserDefaults.standard.bool(forKey: Self.estimateKey) }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let services = ["1826", "1818", "1816"].map { CBUUID(string: $0) }   // FTMS, Cycling Power, CSC
    private let dataChars = ["2AD2", "2A63", "2A5B"].map { CBUUID(string: $0) }
    private var lastCrank: (revs: Int, time: Int, at: Date)?
    /// La última bici conectada: se reconecta directamente sin buscar (funciona en segundo plano).
    private var savedID: UUID? {
        get { UserDefaults.standard.string(forKey: "bikeID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "bikeID") }
    }

    func start() {
        guard central == nil else { return }
        setvbuf(stdout, nil, _IOLBF, 0)   // debug: que cada print llegue a la consola de devicectl al instante
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func stop() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        central?.stopScan()
        central = nil; peripheral = nil
        status = "Parado"; cadence = 0; power = 0; speed = 0
    }

    /// Olvida el sensor guardado y busca otro (para cambiar de bici o de sensor).
    func forget() {
        savedID = nil; deviceName = ""
        stop(); start()
    }

    /// Al volver la app a primer plano sin conexión: busca de nuevo (la búsqueda en segundo plano es lenta).
    func kick() {
        guard let c = central, c.state == .poweredOn, !connected else { return }
        print("BLE kick")
        c.stopScan()
        connectSaved(c)
        c.scanForPeripherals(withServices: services)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("BLE state:", c.state.rawValue)
        guard c.state == .poweredOn else { status = "Bluetooth no disponible"; return }
        status = "Buscando…"
        connectSaved(c)
        c.scanForPeripherals(withServices: services)
    }

    private func connectSaved(_ c: CBCentralManager) {
        guard let id = savedID, let p = c.retrievePeripherals(withIdentifiers: [id]).first else { return }
        print("BLE reconectando a la bici guardada")
        peripheral = p
        p.delegate = self
        c.connect(p)   // sin límite de tiempo: se completa en cuanto la bici emite
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        print("BLE visto:", name, rssi, p.identifier)
        guard namePrefix.isEmpty || name.lowercased().hasPrefix(namePrefix) else { return }
        c.stopScan()
        if let pending = peripheral, pending.identifier != p.identifier { c.cancelPeripheralConnection(pending) }
        peripheral = p
        p.delegate = self
        status = "Conectando…"
        c.connect(p)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.central === c, p.state != .connected else { return }
            print("BLE timeout, reintentando búsqueda")
            c.cancelPeripheralConnection(p)
            self.status = "Reintentando…"
            self.connectSaved(c)
            c.scanForPeripherals(withServices: self.services)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        print("BLE conectado")
        c.stopScan()
        savedID = p.identifier
        deviceName = p.name ?? ""
        lastCrank = nil
        status = "Preparando…"
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        print("BLE fallo:", error as Any)
        status = "Fallo: \(error?.localizedDescription ?? "?") (¿iPhone conectado?)"
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        print("BLE desconectado:", error as Any)
        guard central === c else { return }
        status = "Desconectado, reintentando…"
        c.connect(p)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        print("BLE servicios:", p.services?.map(\.uuid) as Any, error as Any)
        p.services?.forEach { p.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        print("BLE chars", s.uuid, s.characteristics?.map(\.uuid) as Any)
        // Debug: capacidades de la bici (FTMS Feature 2ACC, rango de resistencia 2AD6, rango de potencia 2AD8)
        for ch in s.characteristics ?? [] where ["2ACC", "2AD6", "2AD8"].contains(ch.uuid.uuidString) { p.readValue(for: ch) }
        for ch in s.characteristics ?? [] where dataChars.contains(ch.uuid) {
            p.setNotifyValue(true, for: ch)
            status = "Conectado"
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value else { return }
        print("BLE dato", ch.uuid, d.map { String(format: "%02X", $0) }.joined(separator: " "))
        guard dataChars.contains(ch.uuid) else { return }   // las lecturas de debug no son datos
        switch ch.uuid.uuidString {
        case "2AD2": parseBikeData([UInt8](d))
        case "2A63": parsePower([UInt8](d))
        default: parseCSC([UInt8](d))
        }
        onData?()
    }

    // FTMS Indoor Bike Data: flags(2) + campos según bits
    private func parseBikeData(_ b: [UInt8]) {
        guard b.count >= 2 else { return }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        let f = u16(0); var i = 2
        func has(_ bit: Int) -> Bool { f & (1 << bit) != 0 }
        let campos = ["vel.media", "cad", "cad.media", "dist", "resistencia", "potencia", "pot.media", "energía", "pulso", "MET", "tiempo", "restante"]
        print("BLE flags", String(f, radix: 2), "campos:", campos.enumerated().filter { has($0.offset + 1) }.map(\.element))
        if !has(0), i + 2 <= b.count { speed = Double(u16(i)) / 100; i += 2 }
        if has(1) { i += 2 }                                        // vel. media
        if has(2), i + 2 <= b.count { cadence = u16(i) / 2; i += 2 } // 0.5 rpm
        if has(3) { i += 2 }                                        // cad. media
        if has(4) { i += 3 }                                        // distancia
        if has(5) { if i + 2 <= b.count { print("BLE resistencia:", u16(i)) }; i += 2 }   // resistencia
        if has(6), i + 2 <= b.count, !estimatePower { power = Int(Int16(bitPattern: UInt16(u16(i)))) }
        else { estimateFromCadence() }
    }

    // Cycling Power Measurement: flags(2) + potencia sint16 + campos opcionales (cadencia en bit 5)
    private func parsePower(_ b: [UInt8]) {
        guard b.count >= 4 else { return }
        let f = Int(b[0]) | Int(b[1]) << 8; var i = 4
        if f & 1 != 0 { i += 1 }        // balance de pedales
        if f & 4 != 0 { i += 2 }        // par acumulado
        if f & 16 != 0 { i += 6 }       // vueltas de rueda
        if f & 32 != 0 { crank(b, at: i) }
        if estimatePower { estimateFromCadence(); return }
        power = Int(Int16(bitPattern: UInt16(b[2]) | UInt16(b[3]) << 8))
        speed = speedFor(power)
    }

    // CSC Measurement: flags(1) + vueltas de rueda (bit 0) + vueltas de biela (bit 1). Sin potencia: se estima.
    private func parseCSC(_ b: [UInt8]) {
        guard b.count >= 1 else { return }
        let i = b[0] & 1 != 0 ? 7 : 1
        if b[0] & 2 != 0 { crank(b, at: i) }
        estimateFromCadence()
    }

    /// Cadencia a partir de vueltas acumuladas de biela (uint16) y hora del último evento (uint16, 1/1024 s).
    private func crank(_ b: [UInt8], at i: Int) {
        guard i + 4 <= b.count else { return }
        let revs = Int(b[i]) | Int(b[i + 1]) << 8, time = Int(b[i + 2]) | Int(b[i + 3]) << 8
        defer { if lastCrank?.revs != revs || lastCrank == nil { lastCrank = (revs, time, Date()) } }
        guard let last = lastCrank else { return }
        let dr = (revs - last.revs) & 0xFFFF, dt = (time - last.time) & 0xFFFF
        if dr > 0, dt > 0 { cadence = dr * 60 * 1024 / dt }
        else if Date().timeIntervalSince(last.at) > 3 { cadence = 0 }   // sin pedaladas nuevas: parado
    }

    /// Bicis sin medidor de potencia: W según cadencia y nivel del tornillo, y de ahí la velocidad.
    private func estimateFromCadence() {
        power = Int(Double(cadence) * Self.wattsPerRpmLevel * Double(level))
        speed = speedFor(power)
    }

    private func speedFor(_ w: Int) -> Double { w > 0 ? 1.35 * cbrt(Double(w)) * 3.6 : 0 }
}
