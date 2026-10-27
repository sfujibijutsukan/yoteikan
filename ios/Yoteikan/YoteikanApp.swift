import SwiftUI
import GoogleSignIn

@main struct YoteikanApp: App {
    @StateObject private var plans = PlanStore(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    @StateObject private var calendar = CalendarStore()
    @StateObject private var reminders = ReminderStore()
    @StateObject private var sync = GoogleSyncStore.forLaunch()
    @Environment(\.scenePhase) private var phase
    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-test-data") {
            UserDefaults.standard.removeObject(forKey: "yoteikan.plan.v1")
            UserDefaults.standard.removeObject(forKey: "planner.sidebarLeading")
        }
    }
    var body: some Scene {
        WindowGroup { PlannerView().environmentObject(plans).environmentObject(calendar).environmentObject(reminders).environmentObject(sync)
            .task { await sync.attach(plans) }
            .onOpenURL { _ = GIDSignIn.sharedInstance.handle($0) }
            .onChange(of: plans.plan) { _, value in sync.observe(value) }
            .onReceive(plans.$plan) { reminders.update(plans.demo ? [] : $0.stickies) }
            .onChange(of: phase) { _, value in if value == .active { reminders.update(plans.demo ? [] : plans.plan.stickies); Task { await sync.sync() } } }
            .preferredColorScheme(.light).tint(accent) }
    }
}
