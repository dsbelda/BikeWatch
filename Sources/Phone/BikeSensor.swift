import CoreBluetooth
import Observation

/// Conecta con el primer periférico "SPORT01*" y lee FTMS Indoor Bike Data (0x2AD2)
/// o, si no hay, Cycling Power Measurement (0x2A63).
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

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let namePrefix = "sport01"   // ponytail: filtro por nombre; cambiar si el nombre varía
    private let ftms = CBUUID(string: "1826")
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

    /// Al volver la app a primer plano sin conexión: busca de nuevo (la búsqueda en segundo plano es lenta).
    func kick() {
        guard let c = central, c.state == .poweredOn, !connected else { return }
        print("BLE kick")
        c.stopScan()
        connectSaved(c)
        c.scanForPeripherals(withServices: [ftms])
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        print("BLE state:", c.state.rawValue)
        guard c.state == .poweredOn else { status = "Bluetooth no disponible"; return }
        status = "Buscando…"
        connectSaved(c)
        c.scanForPeripherals(withServices: [ftms])
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
        guard name.isEmpty || name.lowercased().hasPrefix(namePrefix) else { return }
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
            c.scanForPeripherals(withServices: [self.ftms])
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        print("BLE conectado")
        c.stopScan()
        savedID = p.identifier
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
        for ch in s.characteristics ?? [] where ch.uuid == CBUUID(string: "2AD2") || ch.uuid == CBUUID(string: "2A63") {
            p.setNotifyValue(true, for: ch)
            status = "Conectado"
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value else { return }
        print("BLE dato", ch.uuid, d.map { String(format: "%02X", $0) }.joined(separator: " "))
        guard ch.uuid == CBUUID(string: "2AD2") || ch.uuid == CBUUID(string: "2A63") else { return }   // las lecturas de debug no son datos
        if ch.uuid == CBUUID(string: "2AD2") { parseBikeData([UInt8](d)) }
        else { parsePower([UInt8](d)) }
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
        if has(6), i + 2 <= b.count { print("BLE potencia de la bici:", Int16(bitPattern: UInt16(u16(i))), "W, vel. bici:", speed) }
        // La bici estima W solo con rpm (ignora el tornillo): se recalcula con el nivel y de ahí la velocidad.
        power = Int(Double(cadence) * Self.wattsPerRpmLevel * Double(level))
        speed = power > 0 ? 1.35 * cbrt(Double(power)) * 3.6 : 0
    }

    // Cycling Power Measurement: flags(2) + potencia sint16
    private func parsePower(_ b: [UInt8]) {
        guard b.count >= 4 else { return }
        power = Int(Int16(bitPattern: UInt16(b[2]) | UInt16(b[3]) << 8))
    }
}
