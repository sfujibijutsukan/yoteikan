import SwiftUI
import UniformTypeIdentifiers

private struct HourPositions: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct PlannerView: View {
    @EnvironmentObject private var plans: PlanStore
    @EnvironmentObject private var calendar: CalendarStore
    @Environment(\.scenePhase) private var phase
    @State private var showPresets = false
    @State private var showCalendar = false
    @State private var showColors = false
    @State private var showHours = false
    @State private var showNew = false
    @State private var editing: Sticky?
    @State private var selected: UUID?
    @State private var overview = false
    @State private var zoomLevel = 0
    @State private var visibleHour: Int?
    @State private var zoomAnchor = 8
    @State private var viewportTop: CGFloat = 0
    private let zoomSteps: [CGFloat] = [1, 2, 4, 8]
    @State private var dropActive = false
    @State private var moving: UUID?
    @State private var shift: CGFloat = 0
    @State private var stretching: UUID?
    @State private var stretch: CGFloat = 0
    @State private var viewportHeight: CGFloat = 350
    @State private var touchStart = CGPoint.zero
    @State private var touchTask: UUID?
    @State private var inboxFrame = CGRect.zero
    @State private var returningToInbox = false
    @State private var showDetails = false
    @State private var sideShowsDetails = false
    @State private var memoDrafts: [UUID: String] = [:]
    @FocusState private var memoFocused: Bool
    private var selectedTask: Sticky? { plans.today.first { $0.id == selected } }
    private var scale: CGFloat { overview ? max(0.15, (viewportHeight - 32) / CGFloat(plans.hours.totalMinutes)) : 1.55 * zoomSteps[zoomLevel] }
    private var fixed: [FixedEvent] {
        if plans.demo, dayKey(plans.date) == dayKey(Date()) {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--short-events-test") {
                return [FixedEvent(id: "short1", title: "会議5分", start: 495, end: 500), FixedEvent(id: "short2", title: "連絡5分", start: 500, end: 505)]
            }
            #endif
            return [FixedEvent(id: "demo1", title: "チームミーティング", start: 600, end: 660), FixedEvent(id: "demo2", title: "打ち合わせ", start: 840, end: 900)]
        }
        return calendar.events
    }
    private var placed: [Sticky] { plans.today.filter { task in task.start.map { plans.hours.overlaps(start: $0, end: $0 + task.minutes) } ?? false }.sorted { $0.start! < $1.start! } }
    private var inbox: [Sticky] { plans.today.filter { $0.start == nil } }
    private var outside: [Sticky] { plans.today.filter { task in task.start.map { !plans.hours.overlaps(start: $0, end: $0 + task.minutes) } ?? false } }
    private var trayTasks: [Sticky] { inbox + outside }
    private var visibleFixed: [FixedEvent] { fixed.filter { !$0.allDay && plans.hours.overlaps(start: $0.start, end: $0.end) } }
    private var initialHour: Int { min(max(8, plans.hours.start / 60), plans.hours.end / 60 - 1) }
    private var occupied: Int { PlannerMath.occupied(placed.map { ($0.start!, $0.start! + $0.minutes) } + visibleFixed.map { ($0.start, $0.end) }, from: plans.hours.start, to: plans.hours.end) }
    private var slots: [String: TimelineSlot] {
        PlannerMath.layout(placed.map { TimelineItem(id: $0.id.uuidString, start: max(plans.hours.start, $0.start!), end: min(plans.hours.end, $0.start! + $0.minutes)) } + visibleFixed.map { TimelineItem(id: "fixed-" + $0.id, start: max(plans.hours.start, $0.start), end: min(plans.hours.end, $0.end)) })
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
        VStack(spacing: 0) {
            HStack(spacing: 0) { dateBar; header }.padding(.horizontal, 6)
            stats
            if !calendar.connected && !plans.demo {
                Button { showCalendar = true } label: {
                    HStack(spacing: 8) { Image(systemName: "calendar.badge.plus"); Text("カレンダーを接続").font(.system(size: 11, weight: .medium)); Spacer(); Image(systemName: "chevron.right") }.padding(.horizontal, 12).padding(.vertical, 5).foregroundStyle(accent)
                }.accessibilityIdentifier("calendarConnectBanner")
            }
            if !fixed.filter(\.allDay).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(fixed.filter(\.allDay)) { event in Label(event.title, systemImage: "sun.max").font(.caption2).padding(7).background(.white.opacity(0.6), in: Capsule()) } }.padding(.horizontal, 20) }
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) { zoomControls; timeline }
                    .accessibilityElement(children: .contain).accessibilityIdentifier("scheduleZone")
                if wide && !sideShowsDetails {
                    Divider()
                    VStack(spacing: 0) { zoneTitle("詳細メモ"); memoPane }
                        .frame(width: geometry.size.width * 0.28)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("memoZone")
                }
                Divider()
                sideZone.frame(width: wide ? geometry.size.width * 0.25 : max(124, geometry.size.width * 0.34))
            }
        }
        }
        .background(paper).foregroundStyle(ink)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(isPresented: $showPresets) { PresetsView() }
        .sheet(isPresented: $showCalendar) { CalendarSettingsView() }
        .sheet(isPresented: $showColors) { ColorNamesEditor(colors: plans.plan.colors) }
        .sheet(isPresented: $showHours) { PlanningHoursEditor(hours: plans.hours) }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                memoPane.navigationTitle("詳細メモ").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { showDetails = false }.accessibilityIdentifier("closeNotes") } }
            }
        }
        .sheet(isPresented: $showNew) { StickyEditor(task: Sticky(title: "", minutes: 30, day: dayKey(plans.date)), isNew: true) }
        .sheet(item: $editing) { StickyEditor(task: $0, isNew: false) }
        .onChange(of: plans.date) { _, value in calendar.refresh(date: value); selected = nil }
        .onChange(of: phase) { _, value in if value == .active { calendar.refresh(date: plans.date) } }
        .alert("付箋を配置できません", isPresented: Binding(get: { plans.notice != nil }, set: { if !$0 { plans.notice = nil } })) {
            Button("OK") { plans.notice = nil }
        } message: { Text(plans.notice ?? "") }
    }
    private func zoneTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).frame(height: 35).background(paper)
            .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.1)).frame(height: 1) }
    }
    private var memoPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let task = selectedTask {
                Text(task.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                TextEditor(text: Binding(get: { memoDrafts[task.id] ?? task.memo }, set: { memoDrafts[task.id] = $0 }))
                    .font(.system(size: 14)).scrollContentBackground(.hidden)
                    .focused($memoFocused)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("detailMemo")
                Button("メモを保存") {
                    plans.setMemo(task.id, memo: memoDrafts[task.id] ?? task.memo)
                    memoDrafts.removeValue(forKey: task.id)
                    memoFocused = false
                }.disabled((memoDrafts[task.id] ?? task.memo) == task.memo)
                    .accessibilityIdentifier("saveDetailMemo")
            } else {
                Spacer()
                Image(systemName: "note.text").font(.title2)
                Text("付箋を選択").font(.subheadline)
                Spacer()
            }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(paper)
    }
    private var sideZone: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                sideTab("付箋 \(trayTasks.count)", details: false, identifier: "showStickyPool")
                sideTab("詳細", details: true, identifier: "showScheduleDetails")
            }.padding(5).background(paper)
            if sideShowsDetails {
                VStack(spacing: 0) {
                    if let task = selectedTask {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(task.start.map { "\(clockText($0))〜\(clockText($0 + task.minutes))" } ?? "未配置")
                                .font(.system(size: 10, weight: .medium))
                            Text(durationText(task.minutes)).font(.system(size: 11))
                            Button("予定を編集") { editing = task }.font(.system(size: 11))
                                .accessibilityIdentifier("editSideDetail")
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 10)
                    }
                    memoPane
                }.accessibilityElement(children: .contain).accessibilityIdentifier("sideDetail")
            } else {
                inboxView
            }
        }
        .background(returningToInbox ? tones[0] : paper)
        .background { GeometryReader { proxy in Color.clear.onAppear { inboxFrame = proxy.frame(in: .global) }.onChange(of: proxy.frame(in: .global)) { _, frame in inboxFrame = frame } } }
        .accessibilityElement(children: .contain).accessibilityIdentifier("sideZone")
        .accessibilityValue(sideShowsDetails ? "詳細" : "付箋")
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first, let id = UUID(uuidString: raw), plans.today.contains(where: { $0.id == id }) else { return false }
            plans.put(id, at: nil); sideShowsDetails = false; return true
        }
    }
    private func sideTab(_ title: String, details: Bool, identifier: String) -> some View {
        Button {
            memoFocused = false
            if details && selectedTask == nil { selected = placed.first?.id ?? trayTasks.first?.id }
            sideShowsDetails = details
        } label: {
            Text(title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 34)
                .background(sideShowsDetails == details ? accent : .clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(sideShowsDetails == details ? .white : ink)
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            .accessibilityValue(sideShowsDetails == details ? "選択中" : "")
    }
    private var header: some View {
        HStack(spacing: 0) {
            Button { showHours = true } label: {
                Image(systemName: "clock").font(.system(size: 17)).frame(width: 44, height: 44)
            }.accessibilityLabel("計画の時間帯").accessibilityIdentifier("hoursSettings")
            Button { showColors = true } label: {
                Image(systemName: "paintpalette").font(.system(size: 17)).frame(width: 44, height: 44)
            }.accessibilityLabel("付箋の色を設定").accessibilityIdentifier("colorSettings")
            Button { showCalendar = true } label: {
                Image(systemName: "calendar.badge.clock").font(.system(size: 17)).frame(width: 44, height: 44)
            }.accessibilityLabel("カレンダー設定").accessibilityIdentifier("calendarSettings")
        }
    }
    private var dateBar: some View {
        HStack(spacing: 0) {
            Button { changeDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 44) }.accessibilityLabel("前の日")
            Text(plans.date, format: .dateTime.month().day().weekday(.abbreviated)).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75).accessibilityIdentifier("selectedDate")
            Button { changeDay(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 44) }.accessibilityLabel("次の日")
            Spacer(minLength: 0)
            Button { plans.date = Date() } label: { Text("今日").font(.system(size: 10, weight: .semibold)).frame(width: 36, height: 44) }.accessibilityIdentifier("todayButton")
        }
            .contentShape(Rectangle())
            .simultaneousGesture(daySwipeGesture)
            .accessibilityElement(children: .contain).accessibilityIdentifier("dayNavigation")
    }
    private var stats: some View {
            VStack(spacing: 4) {
                timeBar("空き時間", minutes: plans.hours.totalMinutes - occupied, color: accent, identifier: "freeTimeBar")
                timeBar("未配置", minutes: inbox.reduce(0) { $0 + $1.minutes }, color: Color(red: 0.73, green: 0.55, blue: 0.24), identifier: "unplacedTimeBar")
            }.padding(.horizontal, 12).padding(.vertical, 4)
    }
    private func timeBar(_ title: String, minutes: Int, color: Color, identifier: String) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 44, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(ink.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, CGFloat(minutes) / CGFloat(plans.hours.totalMinutes))))
                    }
            }.frame(height: 5).accessibilityHidden(true)
            Text(durationText(minutes)).monospacedDigit().frame(width: 78, alignment: .trailing)
        }.font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.7))
            .accessibilityElement(children: .contain).accessibilityIdentifier(identifier).accessibilityValue(durationText(minutes))
    }
    private var zoomControls: some View {
        HStack(spacing: 0) {
            Text("時間割").font(.system(size: 11, weight: .semibold))
            if plans.demo { Text("デモ").font(.system(size: 8)).padding(3).background(tones[1], in: Capsule()) }
            Spacer(minLength: 0)
            Button { zoomAnchor = selectedTask?.start.map { $0 / 60 } ?? visibleHour ?? initialHour; zoomLevel -= 1 } label: {
                Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44)
            }.disabled(overview || zoomLevel == 0).accessibilityLabel("時間割を縮小").accessibilityIdentifier("zoomOut")
            Text(overview ? "全日" : "\(Int(zoomSteps[zoomLevel]))倍")
                .font(.system(size: 11, weight: .medium)).frame(width: 28)
                .accessibilityIdentifier("zoomLevel")
            Button { if overview { overview = false } else { zoomAnchor = selectedTask?.start.map { $0 / 60 } ?? visibleHour ?? initialHour; zoomLevel += 1 } } label: {
                Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44)
            }.disabled(!overview && zoomLevel == zoomSteps.count - 1).accessibilityLabel("時間割を拡大").accessibilityIdentifier("zoomIn")
            Button { overview.toggle() } label: {
                Image(systemName: overview ? "plus.magnifyingglass" : "rectangle.expand.vertical").frame(width: 44, height: 44)
            }.accessibilityLabel(overview ? "拡大する" : "1日を見る").accessibilityIdentifier("zoomToggle")
        }.padding(.horizontal, 8)
    }
    private func cardHeight(_ minutes: Int) -> CGFloat {
        let slot = CGFloat(minutes) * scale
        return max(0, slot - min(overview ? 1 : 4, slot * 0.25))
    }
    private var timeline: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                        ForEach((plans.hours.start / 60)...(plans.hours.end / 60), id: \.self) { hour in
                            ZStack(alignment: .topLeading) {
                                HStack(spacing: 6) { Text(String(format: "%02d:00", hour)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(ink.opacity(0.55)).frame(width: 34, alignment: .trailing); Rectangle().fill(ink.opacity(0.09)).frame(height: 1) }
                                if !overview && zoomLevel >= 2 && hour < plans.hours.end / 60 {
                                    ForEach(1..<12) { step in
                                        HStack(spacing: 6) {
                                            Text(String(format: ":%02d", step * 5)).font(.system(size: 8, design: .monospaced)).frame(width: 34, alignment: .trailing)
                                            Rectangle().frame(height: 0.5)
                                        }.foregroundStyle(ink.opacity(0.22)).offset(y: CGFloat(step * 5) * scale)
                                    }
                                }
                            }.frame(height: 60 * scale, alignment: .top).id("hour-\(hour)")
                                .background { GeometryReader { proxy in Color.clear.preference(key: HourPositions.self, value: [hour: proxy.frame(in: .global).minY]) } }
                        }
                        }.contentShape(Rectangle()).simultaneousGesture(daySwipeGesture)
                        ForEach(visibleFixed) { event in
                            let start = max(plans.hours.start, event.start)
                            let slot = slots["fixed-" + event.id] ?? TimelineSlot(column: 0, columns: 1)
                            let width = (geometry.size.width - 42) / CGFloat(slot.columns)
                            let height = cardHeight(min(event.end, plans.hours.end) - start)
                            fixedCard(event, height: height).frame(width: width - 3, height: height).clipped()
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(event.title)、\(clockText(event.start))から\(clockText(event.end))、カレンダーの固定予定")
                                .accessibilityIdentifier("fixed-\(event.title)")
                                .offset(x: 40 + width * CGFloat(slot.column), y: CGFloat(start - plans.hours.start) * scale + 2)
                        }
                        ForEach(placed) { task in
                            let visibleStart = max(task.start!, plans.hours.start)
                            let visibleEnd = min(task.start! + task.minutes, plans.hours.end)
                            let collision = conflicts(task)
                            let slot = slots[task.id.uuidString] ?? TimelineSlot(column: 0, columns: 1)
                            let slotCount = slot.columns
                            let width = (geometry.size.width - 42) / CGFloat(slotCount)
                            let height = max(0, cardHeight(visibleEnd - visibleStart) + (stretching == task.id ? stretch : 0))
                            taskCard(task, compact: overview || slotCount > 1, height: height)
                                .frame(width: width - 3, height: height)
                                .overlay { if collision { RoundedRectangle(cornerRadius: 9).stroke(.orange, lineWidth: 1.5).allowsHitTesting(false) } }
                                .overlay(alignment: .bottom) { if !overview && (height >= 54 || stretching == task.id) { resizeHandle(task) } }
                                .contentShape(Rectangle())
                                .overlay(alignment: .topTrailing) {
                                    if selected == task.id && !overview && height >= 32 { moveHandle(task).padding(3) }
                                }
                                .clipped()
                                .overlay(alignment: .top) {
                                    if moving == task.id && !returningToInbox {
                                        let start = task.start! + PlannerMath.snap(Double(shift / scale))
                                        Text("\(clockText(start)) – \(clockText(start + task.minutes))")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(ink, in: Capsule()).foregroundStyle(.white)
                                            .offset(y: -29).allowsHitTesting(false)
                                    }
                                }
                                .offset(x: 40 + width * CGFloat(slot.column), y: CGFloat((moving == task.id ? task.start! : visibleStart) - plans.hours.start) * scale + 2 + (moving == task.id ? shift : 0))
                                .zIndex(moving == task.id || stretching == task.id ? 5 : selected == task.id ? 3 : 1)
                                .onTapGesture { if selected == task.id { editing = task } else { selected = task.id } }
                                .gesture(moveGesture(task))
                                .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in touchStart = value.startLocation; touchTask = task.id })
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("task-\(task.title)")
                                .accessibilityValue("\(clockText(task.start!))|\(task.minutes)")
                                .accessibilityHint(collision ? "ほかの予定と重なっています" : "")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { values, location in
                        guard let raw = values.first, let id = UUID(uuidString: raw), plans.today.contains(where: { $0.id == id }) else { return false }
                        plans.put(id, at: plans.hours.start + PlannerMath.snap(Double(location.y / scale))); selected = id; return true
                    } isTargeted: { dropActive = $0 }
                    .background(dropActive ? accent.opacity(0.05) : Color.clear)
                }.frame(height: CGFloat(plans.hours.end - plans.hours.start) * scale + 18).padding(.top, 12).padding(.horizontal, 5)
            }.coordinateSpace(name: "timelineViewport").accessibilityIdentifier("timeline")
                .onPreferenceChange(HourPositions.self) { positions in
                    visibleHour = positions.filter { $0.value <= viewportTop + 16 }.max(by: { $0.value < $1.value })?.key ?? initialHour
                }
                .task { await Task.yield(); reader.scrollTo("hour-\(initialHour)", anchor: .top) }
                .onChange(of: zoomLevel) { _, _ in
                    Task { @MainActor in
                        await Task.yield()
                        reader.scrollTo("hour-\(zoomAnchor)", anchor: .top)
                    }
                }
                .onChange(of: overview) { _, value in reader.scrollTo("hour-\(value ? plans.hours.start / 60 : initialHour)", anchor: .top) }
                .onChange(of: plans.date) { _, _ in reader.scrollTo("hour-\(overview ? plans.hours.start / 60 : initialHour)", anchor: .top) }
                .onChange(of: plans.hours) { _, _ in
                    selected = nil; moving = nil; stretching = nil; shift = 0; stretch = 0
                    reader.scrollTo("hour-\(overview ? plans.hours.start / 60 : initialHour)", anchor: .top)
                }
        }
        .background(.white.opacity(0.62))
        .background { GeometryReader { proxy in Color.clear.onAppear { viewportHeight = proxy.size.height; viewportTop = proxy.frame(in: .global).minY }.onChange(of: proxy.size) { _, size in viewportHeight = size.height; viewportTop = proxy.frame(in: .global).minY } } }
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.06)).frame(height: 1) }
    }
    private func fixedCard(_ event: FixedEvent, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: overview ? 0 : 5) {
            if height < 44 {
                if height >= 14 { Text(event.title).font(.system(size: 10, weight: .medium)).lineLimit(1) }
            } else if overview { Text(event.title).font(.system(size: 7, weight: .medium)).lineLimit(1) }
            else { HStack { Image(systemName: "lock.fill").font(.system(size: 9)); Text("\(clockText(event.start)) – \(clockText(event.end))").font(.system(size: 10, weight: .medium)); Spacer(minLength: 0) }.foregroundStyle(ink.opacity(0.55))
            if !overview { Text(event.title).font(.system(size: 13, weight: .medium)).lineLimit(2) }
            Spacer(minLength: 0)
            }
        }.padding(height < 44 ? min(height / 2, 2) : 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(red: 0.89, green: 0.91, blue: 0.89), in: RoundedRectangle(cornerRadius: 9)).overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.25)).frame(width: 3).padding(.vertical, 9) }.clipped()
    }
    private func taskCard(_ task: Sticky, compact: Bool, height: CGFloat) -> some View {
        let textColor = plans.paletteColor(for: task.tone).textColor
        let start = (task.start ?? 0) + (moving == task.id ? PlannerMath.snap(Double(shift / scale)) : 0)
        let duration = task.minutes + (stretching == task.id ? PlannerMath.snap(Double(stretch / scale)) : 0)
        return VStack(alignment: .leading, spacing: 4) {
            if height < 44 {
                if height >= 14 { Text(task.title).font(.system(size: 10, weight: .semibold)).lineLimit(1) }
            } else if overview {
                if duration >= 45 { Text(task.title).font(.system(size: 7, weight: .semibold)).lineLimit(1) }
            } else {
            if !compact { Text("\(clockText(start)) – \(clockText(start + duration))").font(.system(size: 10, weight: .medium)).foregroundStyle(textColor.opacity(0.8)) }
            HStack(spacing: 4) { Text(task.title).font(.system(size: compact ? 10 : 12, weight: .semibold)).lineLimit(2); Spacer(minLength: 0); if compact { Text("\(duration)分").font(.system(size: 9)) } }.padding(.trailing, selected == task.id ? 29 : 0)
            Spacer(minLength: 0)
            }
        }.padding(.horizontal, overview ? 3 : 7).padding(.top, height < 44 ? 1 : (compact ? 5 : 7)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(textColor)
            .background(plans.paletteColor(for: task.tone).color, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.22)).frame(width: 3).padding(.vertical, 9) }
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(selected == task.id ? accent : .clear, lineWidth: 2).allowsHitTesting(false) }
            .shadow(color: ink.opacity(moving == task.id ? 0.18 : 0.04), radius: moving == task.id ? 8 : 2, y: 2)
            .clipped()
            .accessibilityLabel("\(task.title)、\(clockText(start))から\(duration)分")
    }
    private func resizeHandle(_ task: Sticky) -> some View {
        ZStack { Color.clear; Capsule().fill(plans.paletteColor(for: task.tone).textColor.opacity(selected == task.id ? 0.6 : 0.35)).frame(width: 24, height: 3) }
            .frame(width: 44, height: 22).contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
                selected = task.id; stretching = task.id
                let newDuration = PlannerMath.duration(task.minutes + PlannerMath.snap(Double(value.translation.height / scale)), start: task.start!, to: plans.hours.end)
                stretch = CGFloat(newDuration - task.minutes) * scale
            }.onEnded { value in
                plans.resize(task.id, minutes: task.minutes + PlannerMath.snap(Double(value.translation.height / scale))); stretching = nil; stretch = 0
            })
            .accessibilityLabel("\(task.title)の長さを変更").accessibilityIdentifier("resize-\(task.title)")
    }
    private func moveHandle(_ task: Sticky) -> some View {
        Image(systemName: "arrow.up.and.down")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 36, height: 26)
            .background(.white.opacity(0.75), in: Capsule())
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { value in
                    updateMove(task, delta: value.translation.height, location: value.location)
                }
                .onEnded { value in
                    finishMove(task, delta: value.translation.height, location: value.location)
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(task.title)の開始時刻を変更")
            .accessibilityHint("上下にドラッグして移動します")
            .accessibilityIdentifier("move-\(task.title)")
    }
    private func updateMove(_ task: Sticky, delta: CGFloat, location: CGPoint) {
        guard let start = task.start else { return }
        selected = task.id; moving = task.id
        returningToInbox = inboxFrame.contains(location)
        let newStart = PlannerMath.start(start + PlannerMath.snap(Double(delta / scale)), duration: task.minutes, from: plans.hours.start, to: plans.hours.end)
        shift = CGFloat(newStart - start) * scale
    }
    private func finishMove(_ task: Sticky, delta: CGFloat, location: CGPoint) {
        defer { moving = nil; shift = 0; returningToInbox = false }
        guard let start = task.start else { return }
        if inboxFrame.contains(location) { plans.put(task.id, at: nil); selected = nil; sideShowsDetails = false }
        else { plans.move(task.id, start: start + PlannerMath.snap(Double(delta / scale))) }
    }
    private func moveGesture(_ task: Sticky) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    let delta = drag.location.y - (touchTask == task.id ? touchStart.y : drag.startLocation.y)
                    updateMove(task, delta: delta, location: drag.location)
                }
            }.onEnded { value in
                if case .second(true, let drag?) = value {
                    let delta = drag.location.y - (touchTask == task.id ? touchStart.y : drag.startLocation.y)
                    finishMove(task, delta: delta, location: drag.location)
                }
                moving = nil; shift = 0; returningToInbox = false
            }
    }
    private var inboxView: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    if trayTasks.isEmpty {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(ink.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .frame(height: 100).accessibilityLabel("未配置の付箋はありません")
                    }
                        ForEach(trayTasks) { task in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(task.title).font(.system(size: 12, weight: .semibold)).lineLimit(3)
                                Text(task.start.map { "時間外 \(clockText($0))" } ?? durationText(task.minutes)).font(.system(size: 10))
                            }.frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading).padding(10)
                                .background(plans.paletteColor(for: task.tone).color, in: RoundedRectangle(cornerRadius: 7))
                                .overlay { RoundedRectangle(cornerRadius: 7).stroke(selected == task.id ? accent : .clear, lineWidth: 2) }
                                .foregroundStyle(plans.paletteColor(for: task.tone).textColor)
                                .onTapGesture { selected = task.id; sideShowsDetails = true }.draggable(task.id.uuidString)
                                .accessibilityElement(children: .ignore).accessibilityLabel("\(task.title)、\(task.minutes)分、\(task.start.map { "時間外 \(clockText($0))" } ?? "未配置")")
                                .accessibilityIdentifier("inbox-\(task.title)")
                        }
                }.padding(8).frame(maxWidth: .infinity, minHeight: 100, alignment: .top)
            }
            VStack(spacing: 4) {
                Button { showPresets = true } label: { Label("プリセット", systemImage: "square.stack").font(.system(size: 11)).frame(maxWidth: .infinity, minHeight: 40) }.accessibilityIdentifier("presetsButton")
                Button { showNew = true } label: { Label("つくる", systemImage: "plus").font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 40).background(accent, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white) }.accessibilityLabel("付箋をつくる").accessibilityIdentifier("newStickyButton")
            }.padding(8)
        }
            .background(returningToInbox ? tones[0] : paper)
            .accessibilityElement(children: .contain).accessibilityIdentifier("inboxTray")
    }
    private var bottomBar: some View {
        HStack {
            Button { plans.restore() } label: { Label("元に戻す", systemImage: "arrow.uturn.backward").font(.system(size: 11, weight: .medium)).frame(height: 42) }.disabled(plans.undo == nil).accessibilityIdentifier("undoButton")
            Spacer()
            Button { showDetails = true } label: { Label("詳細メモ", systemImage: "note.text").font(.system(size: 11)).frame(height: 42) }.accessibilityIdentifier("notesButton")
            if let id = selected, let task = plans.today.first(where: { $0.id == id }) {
                Button { plans.put(id, at: nil); selected = nil } label: { Image(systemName: "tray.and.arrow.down").frame(width: 38, height: 42) }.accessibilityLabel("未配置に戻す").accessibilityIdentifier("unplaceButton")
                Button { editing = task } label: { Image(systemName: "slider.horizontal.3").frame(width: 38, height: 42) }.accessibilityLabel("付箋を編集").accessibilityIdentifier("editButton")
            }
        }.padding(.horizontal, 14).padding(.vertical, 1).background(paper)
    }
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            let horizontal = value.translation.width
            let vertical = value.translation.height
            guard abs(horizontal) >= 60, abs(horizontal) > abs(vertical) * 1.5 else { return }
            changeDay(horizontal < 0 ? 1 : -1)
        }
    }
    private func changeDay(_ offset: Int) { plans.date = Calendar.current.date(byAdding: .day, value: offset, to: plans.date)! }
    private func conflicts(_ task: Sticky) -> Bool {
        guard let start = task.start else { return false }
        return placed.contains { $0.id != task.id && PlannerMath.overlaps(start, start + task.minutes, $0.start!, $0.start! + $0.minutes) } || fixed.contains { !$0.allDay && PlannerMath.overlaps(start, start + task.minutes, $0.start, $0.end) }
    }
}
