import SwiftUI

@main struct YoteikanApp: App {
    @StateObject private var plans = PlanStore(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    @StateObject private var calendar = CalendarStore()
    init() {
        if ProcessInfo.processInfo.arguments.contains("--reset-test-data") {
            UserDefaults.standard.removeObject(forKey: "yoteikan.plan.v1")
        }
    }
    var body: some Scene {
        WindowGroup { PlannerView().environmentObject(plans).environmentObject(calendar).preferredColorScheme(.light).tint(accent) }
    }
}
