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
        #if targetEnvironment(macCatalyst)
        .commands { MacPlannerCommands() }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
struct MacPlannerActions {
    let create: () -> Void
    let selectTab: (Int) -> Void
    let changeDay: (Int) -> Void
    let today: () -> Void
    let zoom: (CGFloat) -> Void
}
private struct MacPlannerActionsKey: FocusedValueKey { typealias Value = MacPlannerActions }
extension FocusedValues {
    var macPlannerActions: MacPlannerActions? {
        get { self[MacPlannerActionsKey.self] }
        set { self[MacPlannerActionsKey.self] = newValue }
    }
}
struct MacPlannerCommands: Commands {
    @FocusedValue(\.macPlannerActions) private var actions
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("付箋をつくる") { actions?.create() }.keyboardShortcut("n").disabled(actions == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("設定…") { actions?.selectTab(2) }.keyboardShortcut(",").disabled(actions == nil)
        }
        CommandMenu("予定") {
            Button("計画") { actions?.selectTab(0) }.keyboardShortcut("1")
            Button("1日表示") { actions?.selectTab(1) }.keyboardShortcut("2")
            Divider()
            Button("前の日") { actions?.changeDay(-1) }.keyboardShortcut("[")
            Button("次の日") { actions?.changeDay(1) }.keyboardShortcut("]")
            Button("今日") { actions?.today() }.keyboardShortcut("t")
            Divider()
            Button("時間割を拡大") { actions?.zoom(1.5) }.keyboardShortcut("+")
            Button("時間割を縮小") { actions?.zoom(1 / 1.5) }.keyboardShortcut("-")
        }
    }
}
#endif
