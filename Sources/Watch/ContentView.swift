import SwiftUI
import WatchKit

/// Como la app Entrenamiento: controles ← métricas → música.
struct ContentView: View {
    let workout: WorkoutManager
    @State private var page = 1
    @State private var finishing = false

    var body: some View {
        Group {
            if workout.running {
                TabView(selection: $page) {
                    ControlsPage(workout: workout, finishing: $finishing).tag(0)
                    MetricsPage(workout: workout).tag(1)
                    NowPlayingView().tag(2)
                }
                .tabViewStyle(.page)
                .sheet(isPresented: $finishing) { FinishView(workout: workout) }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                StartView(workout: workout)
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            }
        }
        .animation(.smooth, value: workout.running)
        .onChange(of: workout.running) { _, on in if on { page = 1 } }
    }
}

struct StartView: View {
    let workout: WorkoutManager
    var body: some View {
        VStack(spacing: 10) {
            Button {
                Task { await workout.start() }
            } label: {
                Image(systemName: "figure.indoor.cycle")
                    .font(.system(size: 44, weight: .semibold))
                    .symbolEffect(.breathe)
                    .frame(width: 96, height: 96)
                    .background(.green.gradient, in: .circle)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            Text("Bici estática").font(.headline)
            Text("Toca para empezar").font(.caption).foregroundStyle(.secondary)
            if workout.today.n > 0 {
                let t = workout.today
                Text("Hoy: \(t.n) · \(mmss(t.secs))\n\(String(format: "%.1f", t.km)) km · \(Int(t.kcal)) kcal")
                    .font(.caption2).multilineTextAlignment(.center).monospacedDigit()
            }
        }
        .task { await workout.loadToday() }
    }
}

struct MetricsPage: View {
    let workout: WorkoutManager
    @State private var lvl = 4.0   // nivel de resistencia: se cambia en la hoja y se manda al iPhone
    @State private var editingLevel = false

    var body: some View {
        let link = workout.link
        let st = link.remote["st"] as? String ?? "Esperando al iPhone…"
        let pausedByUser = workout.paused && !workout.awaitingBike

        VStack(alignment: .leading, spacing: 2) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(mmss(workout.elapsed(at: ctx.date)))
                    .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(pausedByUser ? Color.secondary : .yellow)
                    .contentTransition(.numericText())
            }
            row("heart.fill", "\(Int(workout.heartRate))", "PPM", .red, beating: !workout.paused)
            row("bolt.fill", "\(Int(link.num("pow")))", "W", .yellow)
            row("arrow.clockwise", "\(Int(link.num("cad")))", "RPM", .green)
            HStack {
                Text(String(format: "%.1f km/h", link.num("spd")))
                Spacer()
                Text("Nivel \(Int(lvl))").foregroundStyle(.cyan)
                Spacer()
                Text("\(Int(workout.calories)) kcal").foregroundStyle(.orange)
            }
            .font(.system(.footnote, design: .rounded).weight(.medium)).monospacedDigit()
            if workout.awaitingBike || pausedByUser || st != "Conectado" {
                Label(pausedByUser ? "En pausa" : st, systemImage: pausedByUser ? "pause.fill" : "dot.radiowaves.left.and.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(pausedByUser ? .yellow : .orange)
                    .symbolEffect(.variableColor.iterative, isActive: !pausedByUser)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button { editingLevel = true } label: {
                Image(systemName: "dial.low.fill").font(.footnote).foregroundStyle(.cyan)
                    .frame(width: 26, height: 26).background(.cyan.opacity(0.2), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resistencia")
            .padding(.top, 2)
            .ignoresSafeArea(edges: .top)   // pegado al borde superior
        }
        .sheet(isPresented: $editingLevel) { LevelSheet(lvl: $lvl) }
        .onChange(of: lvl) { _, v in link.send(["lvl": v]) }
        .onChange(of: link.num("lvl")) { _, v in if v >= 1 { lvl = v } }
        .overlay(alignment: .top) {
            if let lap = workout.lap {
                VStack(spacing: 0) {
                    Text("KM \(lap.km)").font(.caption.weight(.bold)).foregroundStyle(.green)
                    Text(mmss(lap.time)).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(.black.opacity(0.85), in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring, value: workout.lap?.km)
    }

    private func row(_ icon: String, _ value: String, _ unit: String, _ color: Color, beating: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
                .symbolEffect(.pulse, isActive: beating)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText())
            Text(unit).font(.caption2).foregroundStyle(color)
        }
    }
}

struct ControlsPage: View {
    let workout: WorkoutManager
    @Binding var finishing: Bool

    var body: some View {
        HStack(spacing: 16) {
            if !workout.awaitingBike {
                control(workout.paused ? "play.fill" : "pause.fill", workout.paused ? "Reanudar" : "Pausa", .yellow) {
                    workout.paused ? workout.resume() : workout.pause()
                }
            }
            control("xmark", workout.awaitingBike ? "Cancelar" : "Finalizar", .red) {
                if workout.awaitingBike { workout.end(save: false) } else { finishing = true }
            }
        }
    }

    private func control(_ icon: String, _ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 64, height: 64)
                    .background(color.opacity(0.25), in: .circle)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            Text(title).font(.caption2)
        }
    }
}

/// Al terminar: esfuerzo opcional (con la corona) y guardar o descartar.
struct FinishView: View {
    let workout: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    @State private var withEffort = false
    @State private var effort = 5

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(mmss(workout.elapsed(at: .now)))
                    .font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                Toggle("Añadir esfuerzo", isOn: $withEffort.animation())
                if withEffort {
                    Picker("Esfuerzo", selection: $effort) {
                        ForEach(1...10, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .frame(height: 50)
                    Text(effortName(effort)).font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    workout.end(save: true, effort: withEffort ? effort : nil); dismiss()
                } label: {
                    Label("Guardar", systemImage: "heart.fill").frame(maxWidth: .infinity)
                }
                .tint(.green)
                Button(role: .destructive) {
                    workout.end(save: false); dismiss()
                } label: {
                    Label("Descartar", systemImage: "trash").frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Terminar")
    }

    private func effortName(_ e: Int) -> String {
        switch e { case ...3: "Fácil"; case 4...6: "Moderado"; case 7...8: "Difícil"; default: "Máximo" }
    }
}

/// Ajuste del nivel de resistencia: corona o botones − / +. Solo responde a la corona mientras está abierta.
struct LevelSheet: View {
    @Binding var lvl: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 6) {
            Text("Resistencia").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { lvl = max(1, lvl - 1) } label: { Image(systemName: "minus") }
                Text("\(Int(lvl))").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .frame(minWidth: 56).contentTransition(.numericText())
                Button { lvl = min(10, lvl + 1) } label: { Image(systemName: "plus") }
            }
            .buttonStyle(.bordered)
            Button("Listo") { dismiss() }.tint(.cyan)
        }
        .focusable()
        .digitalCrownRotation($lvl, from: 1, through: 10, by: 1, sensitivity: .low)
        .animation(.snappy, value: lvl)
    }
}
