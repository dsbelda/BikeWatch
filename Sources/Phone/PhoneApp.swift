import SwiftUI
import Charts

@main
struct PhoneApp: App {
    @State private var m = PhoneModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Entrenar", systemImage: "figure.indoor.cycle") { LiveView(m: m) }
                Tab("Registros", systemImage: "chart.bar.doc.horizontal") { RecordsView(m: m) }
            }
            .tint(.green)
            .onChange(of: phase) { _, p in if p == .active { m.appActive() } }
        }
    }
}

// MARK: - Entrenar

struct LiveView: View {
    let m: PhoneModel
    @State private var finishing = false
    @State private var settings = false
    @AppStorage("maxHR") private var maxHR = 190

    var body: some View {
        NavigationStack {
            Group {
                if m.running { dashboard.transition(.opacity.combined(with: .move(edge: .bottom))) }
                else { idle.transition(.opacity) }
            }
            .animation(.smooth(duration: 0.5), value: m.running)
            .navigationTitle("Entrenar")
            .toolbar {
                Button("Ajustes", systemImage: "slider.horizontal.3") { settings = true }
            }
            .sheet(isPresented: $settings) { SettingsView(sensor: m.sensor) }
            .sheet(isPresented: $finishing) { FinishSheet(m: m) }
        }
    }

    private var idle: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image(systemName: "figure.indoor.cycle")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.breathe)
                        .frame(width: 140, height: 140)
                        .background(
                            Circle().fill(.green.gradient)
                                .shadow(color: .green.opacity(0.5), radius: 30)
                        )
                    Text("Listo para pedalear").font(.title2.weight(.bold))
                    Text("Empieza desde el reloj, o di\n«Oye Siri, empezar BikeWatch».")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if let last = m.records.first {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Último entrenamiento").font(.headline)
                            Spacer()
                            Text(last.date, format: .relative(presentation: .named))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        RecordSummary(r: last)
                    }
                }
            }
            .padding()
        }
    }

    private var dashboard: some View {
        let connected = m.sensor.connected
        let hist = m.history
        let hr = m.link.num("hr")
        return ScrollView {
            VStack(spacing: 16) {
                StatusPill(text: m.paused && connected ? "En pausa" : m.sensor.status,
                           color: m.paused && connected ? .yellow : connected ? .green : .orange,
                           searching: !connected)

                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(mmss(m.elapsed(at: ctx.date)))
                        .font(.system(size: 80, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(m.paused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .contentTransition(.numericText(countsDown: false))
                        .animation(.snappy, value: Int(m.elapsed(at: ctx.date)))
                }

                HeartCard(hr: hr, maxHR: maxHR, peak: hist.map(\.hr).max() ?? 0, beating: !m.paused)

                Stepper("Resistencia: nivel \(m.sensor.level)", value: Bindable(m.sensor).level, in: 1...10)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(icon: "bolt.fill", unit: "W", value: "\(m.sensor.power)",
                               detail: "media \(Int(avg(hist.map(\.pow))))", color: .yellow)
                    MetricCard(icon: "arrow.clockwise", unit: "rpm", value: "\(m.sensor.cadence)",
                               detail: "media \(Int(avg(hist.map(\.cad))))", color: .green)
                    MetricCard(icon: "speedometer", unit: "km/h", value: String(format: "%.1f", m.sensor.speed),
                               detail: "media \(String(format: "%.1f", avg(hist.map(\.spd))))", color: .cyan)
                    MetricCard(icon: "map", unit: "km", value: String(format: "%.2f", m.km),
                               detail: "distancia", color: .blue)
                    MetricCard(icon: "flame.fill", unit: "kcal", value: "\(Int(m.link.num("kcal")))",
                               detail: "activas", color: .orange)
                    MetricCard(icon: "flag.checkered", unit: "parciales", value: "\(m.splits.count)",
                               detail: m.splits.last.map { "último \(mmss($0.time))" } ?? "cada km", color: .mint)
                }

                if !m.splits.isEmpty { SplitsCard(splits: m.splits) }

                ChartCard(title: "Pulso", icon: "heart.fill", color: .red, samples: hist, y: \.hr)
                ChartCard(title: "Potencia", icon: "bolt.fill", color: .yellow, samples: hist, y: \.pow)
                ChartCard(title: "Cadencia", icon: "arrow.clockwise", color: .green, samples: hist, y: \.cad)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { controls }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button { m.togglePause() } label: {
                    Label(m.paused ? "Reanudar" : "Pausa", systemImage: m.paused ? "play.fill" : "pause.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button { finishing = true } label: {
                    Label("Finalizar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).tint(.red)
            }
            .controlSize(.large)
            .font(.headline)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .sensoryFeedback(.impact, trigger: m.paused)
    }
}

// MARK: - Finalizar

struct FinishSheet: View {
    let m: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @State private var withEffort = false
    @State private var effort = 5.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        stat(mmss(m.elapsed(at: .now)), "tiempo")
                        stat(String(format: "%.2f", m.km), "km")
                        stat("\(Int(m.link.num("kcal")))", "kcal")
                    }
                }
                Section {
                    Toggle("Añadir esfuerzo", isOn: $withEffort.animation(.snappy))
                    if withEffort {
                        VStack(spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(Int(effort))").font(.system(size: 44, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText()).animation(.snappy, value: effort)
                                Text(effortLabel(Int(effort))).font(.headline).foregroundStyle(effortColor)
                            }
                            Slider(value: $effort, in: 1...10, step: 1).tint(effortColor)
                        }
                        .sensoryFeedback(.selection, trigger: effort)
                    }
                } footer: {
                    Text("Opcional. Se guarda junto al entrenamiento en Fitness y Salud.")
                }
                Section {
                    Button("Guardar en Salud y registros", systemImage: "heart.fill") { finish(.health) }
                    Button("Solo en registros", systemImage: "tray.and.arrow.down") { finish(.recordOnly) }
                    Button("Descartar", systemImage: "trash", role: .destructive) { finish(.discard) }
                }
            }
            .navigationTitle("Finalizar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Seguir", systemImage: "xmark") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    private var effortColor: Color {
        switch Int(effort) { case ...3: .green; case 4...6: .yellow; case 7...8: .orange; default: .red }
    }

    private func finish(_ c: Choice) {
        m.finish(c, effort: withEffort ? Int(effort) : nil)
        dismiss()
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack {
            Text(v).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    let sensor: BikeSensor
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BikeSensor.prefixKey) private var prefix = ""
    @AppStorage(BikeSensor.estimateKey) private var estimate = false
    @AppStorage("voice") private var voice = true
    @AppStorage("voiceKm") private var voiceKm = true
    @AppStorage("voiceMinutes") private var voiceMinutes = 5
    @AppStorage("maxHR") private var maxHR = 190

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Conectado a", value: sensor.deviceName.isEmpty ? sensor.status : sensor.deviceName)
                    TextField("Filtro por nombre (vacío = cualquiera)", text: $prefix)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Estimar potencia con el nivel", systemImage: "function", isOn: $estimate)
                    Button("Olvidar y buscar otro sensor", systemImage: "arrow.triangle.2.circlepath") { sensor.forget() }
                } header: {
                    Text("Sensor")
                } footer: {
                    Text("Vale cualquier bici o sensor Bluetooth con FTMS, potencia (Cycling Power) o cadencia (Speed and Cadence). Si el sensor no mide potencia, se estima con la cadencia y el nivel.")
                }
                Section {
                    Toggle("Avisos por voz", systemImage: "speaker.wave.2.fill", isOn: $voice.animation())
                    if voice {
                        Toggle("Cada kilómetro", systemImage: "flag.checkered", isOn: $voiceKm)
                        Picker("Cada", systemImage: "timer", selection: $voiceMinutes) {
                            Text("Nunca").tag(0)
                            ForEach([1, 5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
                        }
                    }
                } header: {
                    Text("Guía en los auriculares")
                } footer: {
                    Text("Te dice el parcial, la potencia y el pulso. La música baja de volumen mientras habla.")
                }
                Section {
                    Stepper("Pulso máximo: \(maxHR)", value: $maxHR, in: 140...220)
                } header: {
                    Text("Zonas de pulso")
                } footer: {
                    Text("Si no lo conoces, una estimación es 220 menos tu edad.")
                }
                Section {
                    ForEach(1...10, id: \.self) { l in
                        LabeledContent("Nivel \(l)", value: "\(Int(70 * BikeSensor.wattsPerRpmLevel * Double(l))) W · \(Int(1.35 * cbrt(70 * BikeSensor.wattsPerRpmLevel * Double(l)) * 3.6)) km/h")
                    }
                } header: {
                    Text("Niveles de resistencia")
                } footer: {
                    Text("Equivalencia a 70 rpm. Son estimaciones: la bici no mide la resistencia.")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Listo", systemImage: "checkmark") { dismiss() } }
        }
    }
}

// MARK: - Registros

struct RecordsView: View {
    let m: PhoneModel

    private var days: [(day: Date, items: [Record])] {
        Dictionary(grouping: m.records) { Calendar.current.startOfDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                if !m.records.isEmpty {
                    Section("Últimos 7 días") { WeekSummary(records: m.records) }
                }
                ForEach(days, id: \.day) { d in
                    Section {
                        ForEach(d.items) { r in
                            NavigationLink(value: r.id) { RecordRow(r: r) }
                        }
                        .onDelete { o in m.deleteRecords(at: IndexSet(o.compactMap { i in m.records.firstIndex { $0.id == d.items[i].id } })) }
                    } header: {
                        HStack {
                            Text(d.day, format: .dateTime.weekday(.wide).day().month())
                            Spacer()
                            Text("\(mmss(d.items.map(\.duration).reduce(0, +))) · \(String(format: "%.1f", d.items.map(\.km).reduce(0, +))) km")
                                .monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if m.records.isEmpty {
                    ContentUnavailableView("Sin entrenamientos", systemImage: "figure.indoor.cycle",
                                           description: Text("Aquí aparecerán tus sesiones."))
                }
            }
            .navigationTitle("Registros")
            .navigationDestination(for: UUID.self) { id in
                if let r = m.records.first(where: { $0.id == id }) { RecordDetail(r: r) }
            }
        }
    }
}

struct WeekSummary: View {
    let records: [Record]
    var body: some View {
        let week = records.filter { $0.date > .now.addingTimeInterval(-7 * 86400) }
        HStack {
            stat("\(week.count)", "sesiones")
            stat(mmss(week.map(\.duration).reduce(0, +)), "tiempo")
            stat(String(format: "%.1f", week.map(\.km).reduce(0, +)), "km")
            stat("\(Int(week.map(\.kcal).reduce(0, +)))", "kcal")
        }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack {
            Text(v).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecordRow: View {
    let r: Record
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.indoor.cycle")
                .font(.title3).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.green.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.date, format: .dateTime.hour().minute())
                    .font(.headline)
                Text("\(mmss(r.duration)) · \(String(format: "%.1f", r.km)) km · \(Int(r.kcal)) kcal")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if let e = r.effort {
                Text("\(e)").font(.caption.weight(.bold)).frame(width: 24, height: 24)
                    .background(.orange.opacity(0.25), in: .circle).foregroundStyle(.orange)
                    .accessibilityLabel("Esfuerzo \(e)")
            }
            Image(systemName: r.inHealth ? "heart.fill" : "tray.full")
                .foregroundStyle(r.inHealth ? .pink : .secondary)
                .accessibilityLabel(r.inHealth ? "Guardado en Salud" : "Solo en registros")
        }
    }
}

struct RecordSummary: View {
    let r: Record
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(icon: "timer", unit: "tiempo", value: mmss(r.duration), detail: nil, color: .primary)
            MetricCard(icon: "map", unit: "km", value: String(format: "%.2f", r.km), detail: nil, color: .blue)
            MetricCard(icon: "flame.fill", unit: "kcal", value: "\(Int(r.kcal))", detail: nil, color: .orange)
            MetricCard(icon: "bolt.fill", unit: "W medios", value: "\(Int(r.avgPow))", detail: "máx \(Int(r.maxPow))", color: .yellow)
            MetricCard(icon: "arrow.clockwise", unit: "rpm medias", value: "\(Int(r.avgCad))", detail: nil, color: .green)
            MetricCard(icon: "heart.fill", unit: "ppm medias", value: "\(Int(r.avgHR))", detail: "máx \(Int(r.maxHR))", color: .red)
        }
    }
}

struct RecordDetail: View {
    let r: Record
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Label(r.inHealth ? "En Salud" : "Solo registros", systemImage: r.inHealth ? "heart.fill" : "tray.full")
                        .foregroundStyle(r.inHealth ? .pink : .secondary)
                    if let e = r.effort {
                        Label("Esfuerzo \(e) · \(effortLabel(e))", systemImage: "gauge.with.dots.needle.67percent")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.subheadline.weight(.semibold))
                RecordSummary(r: r)
                if let s = r.splits, !s.isEmpty { SplitsCard(splits: s) }
                ChartCard(title: "Pulso", icon: "heart.fill", color: .red, samples: r.samples, y: \.hr)
                ChartCard(title: "Potencia", icon: "bolt.fill", color: .yellow, samples: r.samples, y: \.pow)
                ChartCard(title: "Cadencia", icon: "arrow.clockwise", color: .green, samples: r.samples, y: \.cad)
                ChartCard(title: "Velocidad", icon: "speedometer", color: .cyan, samples: r.samples, y: \.spd)
            }
            .padding()
        }
        .navigationTitle(r.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Piezas comunes

struct StatusPill: View {
    let text: String, color: Color
    var searching = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: searching ? "dot.radiowaves.left.and.right" : "circle.fill")
                .font(searching ? .subheadline : .system(size: 8))
                .symbolEffect(.variableColor.iterative, isActive: searching)
                .foregroundStyle(color)
            Text(text).font(.subheadline.weight(.semibold))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular.tint(color.opacity(0.25)), in: .capsule)
        .animation(.smooth, value: text)
    }
}

/// Pulso con zona (1–5) según el pulso máximo de los ajustes.
struct HeartCard: View {
    let hr: Double, maxHR: Int, peak: Double, beating: Bool

    private var zone: Int {
        let pct = hr / Double(maxHR)
        return hr <= 0 ? 0 : pct < 0.6 ? 1 : pct < 0.7 ? 2 : pct < 0.8 ? 3 : pct < 0.9 ? 4 : 5
    }
    private let zoneColors: [Color] = [.blue, .green, .yellow, .orange, .red]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 40)).foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: beating && hr > 0)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(hr))").font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText()).animation(.snappy, value: Int(hr))
                    Text("ppm").font(.headline).foregroundStyle(.secondary)
                }
                Text("máx \(Int(peak))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(zone == 0 ? "—" : "Zona \(zone)").font(.headline)
                    .foregroundStyle(zone == 0 ? .secondary : zoneColors[zone - 1])
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { z in
                        Capsule().fill(z <= zone ? zoneColors[z - 1] : Color.secondary.opacity(0.25))
                            .frame(width: 14, height: z == zone ? 22 : 14)
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.4), value: zone)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
    }
}

struct MetricCard: View {
    let icon: String, unit: String, value: String
    let detail: String?
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(unit, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText()).animation(.snappy, value: value)
                .lineLimit(1).minimumScaleFactor(0.5)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22))
        .scrollTransition { c, phase in
            c.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.96)
        }
    }
}

/// Parciales por km: tiempo con barra relativa (más larga = más lento).
struct SplitsCard: View {
    let splits: [Split]
    var body: some View {
        let slowest = splits.map(\.time).max() ?? 1
        let fastest = splits.map(\.time).min() ?? 0
        VStack(alignment: .leading, spacing: 10) {
            Label("Parciales", systemImage: "flag.checkered").font(.subheadline.weight(.semibold)).foregroundStyle(.mint)
            ForEach(splits.reversed()) { s in
                HStack(spacing: 10) {
                    Text("\(s.km)").font(.subheadline.weight(.bold)).frame(width: 24, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(s.time == fastest ? Color.mint : Color.mint.opacity(0.4))
                            .frame(width: max(8, g.size.width * s.time / slowest))
                    }
                    .frame(height: 8)
                    Text(mmss(s.time)).font(.subheadline.weight(.semibold)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    Text("\(Int(s.avgPow)) W").font(.caption).foregroundStyle(.yellow).frame(width: 46, alignment: .trailing)
                    Text("\(Int(s.avgHR))").font(.caption).foregroundStyle(.red).frame(width: 30, alignment: .trailing)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22))
    }
}

struct ChartCard: View {
    let title: String, icon: String, color: Color
    let samples: [Sample]
    let y: KeyPath<Sample, Double>
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                Spacer()
                if let peak = samples.map({ $0[keyPath: y] }).max(), peak > 0 {
                    Text("máx \(Int(peak))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Chart(samples) { s in
                AreaMark(x: .value("t", s.t), y: .value(title, s[keyPath: y]))
                    .foregroundStyle(.linearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", s.t), y: .value(title, s[keyPath: y]))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .frame(height: 120)
            .overlay {
                if samples.isEmpty { Text("Sin datos aún").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22))
        .scrollTransition { c, phase in
            c.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }
}
