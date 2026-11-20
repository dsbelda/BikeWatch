import AppIntents

/// "Oye Siri, empezar BikeWatch", y disponible en la app Atajos y la Smart Stack del reloj.
struct StartRideIntent: AppIntent {
    static let title: LocalizedStringResource = "Empezar bici estática"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await WorkoutManager.shared.start()
        return .result()
    }
}

struct BikeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRideIntent(),
                    phrases: ["Empezar \(.applicationName)", "Entrenar con \(.applicationName)"],
                    shortTitle: "Empezar bici",
                    systemImageName: "figure.indoor.cycle")
    }
}
