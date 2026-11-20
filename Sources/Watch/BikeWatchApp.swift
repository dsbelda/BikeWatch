import SwiftUI

@main
struct BikeWatchApp: App {
    var body: some Scene {
        WindowGroup { ContentView(workout: WorkoutManager.shared) }
    }
}
