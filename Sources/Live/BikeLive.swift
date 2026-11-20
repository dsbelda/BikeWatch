import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BikeLiveBundle: WidgetBundle {
    var body: some Widget { RideLiveActivity() }
}

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideAttributes.self) { ctx in
            LockScreenView(s: ctx.state)
                .activityBackgroundTint(.black.opacity(0.6))
                .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(String(format: "%.2f km", s.km)) } icon: { Image(systemName: "figure.indoor.cycle") }
                        .font(.headline).foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label("\(s.hr)", systemImage: "heart.fill").font(.headline).foregroundStyle(.red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Elapsed(s: s).font(.system(size: 40, weight: .bold, design: .rounded))
                        Spacer()
                        Label("\(s.power) W", systemImage: "bolt.fill").font(.title3.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.indoor.cycle").foregroundStyle(.green)
            } compactTrailing: {
                Elapsed(s: s).frame(maxWidth: 56).font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: s.paused ? "pause.fill" : "figure.indoor.cycle").foregroundStyle(.green)
            }
        }
    }
}

/// Cronómetro que avanza solo (sin actualizaciones de la app); fijo cuando está en pausa.
struct Elapsed: View {
    let s: RideAttributes.ContentState
    var body: some View {
        Group {
            if s.paused { Text(mmss(s.elapsed)) }
            else { Text(timerInterval: s.timerStart...Date.distantFuture, countsDown: false) }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

struct LockScreenView: View {
    let s: RideAttributes.ContentState
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: s.paused ? "pause.circle.fill" : "figure.indoor.cycle")
                .font(.system(size: 36)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.paused ? "En pausa" : "BikeWatch").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Elapsed(s: s).font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.2f km", s.km)).font(.headline).monospacedDigit()
                Label("\(s.hr)", systemImage: "heart.fill").font(.subheadline).foregroundStyle(.red)
                Label("\(s.power) W", systemImage: "bolt.fill").font(.subheadline).foregroundStyle(.yellow)
            }
        }
        .padding()
    }
}
