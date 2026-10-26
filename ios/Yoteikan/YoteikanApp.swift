import SwiftUI

@main struct YoteikanApp: App {
    @StateObject private var plans = PlanStore(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    @StateObject private var calendar = CalendarStore()
    @StateObject private var reminders = ReminderStore()
    @Environment(\.scenePhase) private var phase
    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-test-data") {
            UserDefaults.standard.removeObject(forKey: "yoteikan.plan.v1")
        }
    }
    var body: some Scene {
        WindowGroup { PlannerView().environmentObject(plans).environmentObject(calendar).environmentObject(reminders)
            .onReceive(plans.$plan) { reminders.update(plans.demo ? [] : $0.stickies) }
            .onChange(of: phase) { _, value in if value == .active { reminders.update(plans.demo ? [] : plans.plan.stickies) } }
            .preferredColorScheme(.light).tint(accent) }
    }
}
