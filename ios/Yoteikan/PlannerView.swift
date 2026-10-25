import SwiftUI
import UniformTypeIdentifiers

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
    private var scale: CGFloat { overview ? max(0.15, (viewportHeight - 32) / CGFloat(plans.hours.totalMinutes)) : 1.55 }
    private var fixed: [FixedEvent] {
        if plans.demo, dayKey(plans.date) == dayKey(Date()) {
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
        VStack(spacing: 0) {
            header
            dateBar
            stats
            if !calendar.connected && !plans.demo {
                Button { showCalendar = true } label: {
                    HStack(spacing: 8) { Image(systemName: "calendar.badge.plus"); Text("カレンダーを接続").font(.system(size: 12, weight: .medium)); Spacer(); Image(systemName: "chevron.right") }.padding(.horizontal, 20).padding(.vertical, 10).foregroundStyle(accent)
                }.accessibilityIdentifier("calendarConnectBanner")
            }
            if !fixed.filter(\.allDay).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(fixed.filter(\.allDay)) { event in Label(event.title, systemImage: "sun.max").font(.caption2).padding(7).background(.white.opacity(0.6), in: Capsule()) } }.padding(.horizontal, 20) }
            }
            timeline
            inboxView
        }
        .background(paper).foregroundStyle(ink)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(isPresented: $showPresets) { PresetsView() }
        .sheet(isPresented: $showCalendar) { CalendarSettingsView() }
        .sheet(isPresented: $showColors) { ColorNamesEditor(colors: plans.plan.colors) }
        .sheet(isPresented: $showHours) { PlanningHoursEditor(hours: plans.hours) }
        .sheet(isPresented: $showNew) { StickyEditor(task: Sticky(title: "", minutes: 30, day: dayKey(plans.date)), isNew: true) }
        .sheet(item: $editing) { StickyEditor(task: $0, isNew: false) }
        .onChange(of: plans.date) { _, value in calendar.refresh(date: value); selected = nil }
        .onChange(of: phase) { _, value in if value == .active { calendar.refresh(date: plans.date) } }
        .alert("付箋を配置できません", isPresented: Binding(get: { plans.notice != nil }, set: { if !$0 { plans.notice = nil } })) {
            Button("OK") { plans.notice = nil }
        } message: { Text(plans.notice ?? "") }
    }
    private var header: some View {
        HStack {
            Text("予定館").font(.system(size: 22, weight: .semibold, design: .serif))
            if plans.demo {
                Text("デモ").font(.system(size: 9)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(tones[1], in: Capsule())
            }
            Spacer()
            Button { showHours = true } label: {
                Image(systemName: "clock").font(.system(size: 19))
                    .frame(width: 44, height: 44).background(.white.opacity(0.8), in: Circle())
            }.accessibilityLabel("計画の時間帯").accessibilityIdentifier("hoursSettings")
            Button { showColors = true } label: {
                Image(systemName: "paintpalette").font(.system(size: 19))
                    .frame(width: 44, height: 44).background(.white.opacity(0.8), in: Circle())
            }.accessibilityLabel("付箋の色を設定").accessibilityIdentifier("colorSettings")
            Button { showCalendar = true } label: {
                Image(systemName: "calendar.badge.clock").font(.system(size: 19))
                    .frame(width: 44, height: 44).background(.white.opacity(0.8), in: Circle())
            }.accessibilityLabel("カレンダー設定").accessibilityIdentifier("calendarSettings")
        }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 8)
    }
    private var dateBar: some View {
        HStack(spacing: 9) {
            Button { changeDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 36) }.accessibilityLabel("前の日")
            Text(plans.date, format: .dateTime.month().day().weekday(.wide)).font(.system(size: 15, weight: .semibold)).accessibilityIdentifier("selectedDate")
            Button { changeDay(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 36) }.accessibilityLabel("次の日")
            Spacer(minLength: 0)
            Button { plans.date = Date() } label: { Text("今日").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7).background(.white, in: Capsule()) }.accessibilityIdentifier("todayButton")
        }.padding(.horizontal, 12)
            .contentShape(Rectangle())
            .simultaneousGesture(daySwipeGesture)
            .accessibilityElement(children: .contain).accessibilityIdentifier("dayNavigation")
    }
    private var stats: some View {
        HStack(spacing: 0) {
            stat("空き時間", durationText(plans.hours.totalMinutes - occupied))
            Rectangle().fill(ink.opacity(0.10)).frame(width: 1, height: 31)
            stat("未配置", durationText(inbox.reduce(0) { $0 + $1.minutes }))
            Spacer(minLength: 0)
            Button { overview.toggle() } label: { VStack(spacing: 5) { Image(systemName: overview ? "plus.magnifyingglass" : "rectangle.expand.vertical").font(.system(size: 17)); Text(overview ? "拡大する" : "1日を見る").font(.system(size: 10)) }.frame(width: 70, height: 55) }.accessibilityIdentifier("zoomToggle")
        }.padding(.horizontal, 22).padding(.vertical, 12)
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 10)).foregroundStyle(ink.opacity(0.55)); Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)) }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, title == "未配置" ? 18 : 0)
    }
    private var timeline: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                        ForEach((plans.hours.start / 60)...(plans.hours.end / 60), id: \.self) { hour in
                            HStack(alignment: .center, spacing: 10) { Text(String(format: "%02d:00", hour)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(ink.opacity(0.4)).frame(width: 43, alignment: .trailing); Rectangle().fill(ink.opacity(0.09)).frame(height: 1) }.frame(height: 60 * scale, alignment: .top).id(hour)
                        }
                        }.contentShape(Rectangle()).simultaneousGesture(daySwipeGesture)
                        ForEach(visibleFixed) { event in
                            let start = max(plans.hours.start, event.start)
                            let slot = slots["fixed-" + event.id] ?? TimelineSlot(column: 0, columns: 1)
                            let width = (geometry.size.width - 68) / CGFloat(slot.columns)
                            fixedCard(event).frame(width: width - 3, height: max(overview ? 3 : 20, CGFloat(min(event.end, plans.hours.end) - start) * scale - (overview ? 1 : 4))).offset(x: 58 + width * CGFloat(slot.column), y: CGFloat(start - plans.hours.start) * scale + 2)
                        }
                        ForEach(placed) { task in
                            let visibleStart = max(task.start!, plans.hours.start)
                            let visibleEnd = min(task.start! + task.minutes, plans.hours.end)
                            let collision = conflicts(task)
                            let slot = slots[task.id.uuidString] ?? TimelineSlot(column: 0, columns: 1)
                            let slotCount = slot.columns
                            let width = (geometry.size.width - 68) / CGFloat(slotCount)
                            taskCard(task, compact: overview || slotCount > 1)
                                .frame(width: width - 3, height: max(overview ? 3 : 24, CGFloat(visibleEnd - visibleStart) * scale - (overview ? 1 : 4) + (stretching == task.id ? stretch : 0)))
                                .overlay { if collision { RoundedRectangle(cornerRadius: 9).stroke(.orange, lineWidth: 1.5).allowsHitTesting(false) } }
                                .overlay(alignment: .bottom) { if !overview { resizeHandle(task) } }
                                .contentShape(Rectangle())
                                .overlay(alignment: .topTrailing) {
                                    if selected == task.id && !overview { moveHandle(task).padding(3) }
                                }
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
                                .offset(x: 58 + width * CGFloat(slot.column), y: CGFloat((moving == task.id ? task.start! : visibleStart) - plans.hours.start) * scale + 2 + (moving == task.id ? shift : 0))
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
                }.frame(height: CGFloat(plans.hours.end - plans.hours.start) * scale + 18).padding(.top, 12).padding(.horizontal, 10)
            }.accessibilityIdentifier("timeline")
                .task { await Task.yield(); reader.scrollTo(initialHour, anchor: .top) }
                .onChange(of: overview) { _, value in reader.scrollTo(value ? plans.hours.start / 60 : initialHour, anchor: .top) }
                .onChange(of: plans.date) { _, _ in reader.scrollTo(overview ? plans.hours.start / 60 : initialHour, anchor: .top) }
                .onChange(of: plans.hours) { _, _ in
                    selected = nil; moving = nil; stretching = nil; shift = 0; stretch = 0
                    reader.scrollTo(overview ? plans.hours.start / 60 : initialHour, anchor: .top)
                }
        }
        .background(.white.opacity(0.62))
        .background { GeometryReader { proxy in Color.clear.onAppear { viewportHeight = proxy.size.height }.onChange(of: proxy.size.height) { _, height in viewportHeight = height } } }
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.06)).frame(height: 1) }
    }
    private func fixedCard(_ event: FixedEvent) -> some View {
        VStack(alignment: .leading, spacing: overview ? 0 : 5) {
            if overview { Text(event.title).font(.system(size: 7, weight: .medium)).lineLimit(1) }
            else { HStack { Image(systemName: "lock.fill").font(.system(size: 9)); Text("\(clockText(event.start)) – \(clockText(event.end))").font(.system(size: 10, weight: .medium)); Spacer(minLength: 0) }.foregroundStyle(ink.opacity(0.55))
            if !overview { Text(event.title).font(.system(size: 13, weight: .medium)).lineLimit(2) }
            Spacer(minLength: 0)
            }
        }.padding(overview ? 2 : 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(red: 0.89, green: 0.91, blue: 0.89), in: RoundedRectangle(cornerRadius: 9)).overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.25)).frame(width: 3).padding(.vertical, 9) }.clipped().accessibilityElement(children: .ignore).accessibilityLabel("\(event.title)、\(clockText(event.start))から\(clockText(event.end))、カレンダーの固定予定").accessibilityIdentifier("fixed-\(event.title)")
    }
    private func taskCard(_ task: Sticky, compact: Bool) -> some View {
        let textColor = plans.paletteColor(for: task.tone).textColor
        let start = (task.start ?? 0) + (moving == task.id ? PlannerMath.snap(Double(shift / scale)) : 0)
        let duration = task.minutes + (stretching == task.id ? PlannerMath.snap(Double(stretch / scale)) : 0)
        return VStack(alignment: .leading, spacing: 4) {
            if overview {
                if duration >= 45 { Text(task.title).font(.system(size: 7, weight: .semibold)).lineLimit(1) }
            } else {
            if !compact { Text("\(clockText(start)) – \(clockText(start + duration))").font(.system(size: 10, weight: .medium)).foregroundStyle(textColor.opacity(0.8)) }
            HStack(spacing: 4) { Text(task.title).font(.system(size: compact ? 10 : 14, weight: .semibold)).lineLimit(1); Spacer(minLength: 0); if compact { Text("\(duration)分").font(.system(size: 9)) } }.padding(.trailing, selected == task.id ? 29 : 0)
            Spacer(minLength: 0)
            }
        }.padding(.horizontal, overview ? 3 : 12).padding(.top, overview ? 1 : (compact ? 5 : 9)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        if inboxFrame.contains(location) { plans.put(task.id, at: nil); selected = nil }
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
        VStack(alignment: .leading, spacing: 11) {
            HStack { Text(outside.isEmpty ? "未配置" : "未配置・時間外").font(.system(size: 14, weight: .semibold)); Text("\(trayTasks.count)").font(.system(size: 10, weight: .bold)).padding(5).background(ink.opacity(0.06), in: Circle()); Spacer(); Button { showPresets = true } label: { Label("プリセット", systemImage: "square.stack").font(.system(size: 11, weight: .medium)) }.accessibilityIdentifier("presetsButton") }
            if trayTasks.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 64)
                    .accessibilityLabel("未配置の付箋はありません")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(trayTasks) { task in
                            VStack(alignment: .leading, spacing: 10) { Text(task.title).font(.system(size: 13, weight: .semibold)).lineLimit(1); HStack { Text(task.start.map { "時間外 \(clockText($0))" } ?? durationText(task.minutes)).font(.system(size: 11)); Spacer(); Image(systemName: "arrow.up.left").font(.system(size: 10)) } }.padding(12).frame(width: 123, height: 73).background(plans.paletteColor(for: task.tone).color, in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(plans.paletteColor(for: task.tone).textColor)
                                .onTapGesture { editing = task }.draggable(task.id.uuidString)
                                .accessibilityElement(children: .ignore).accessibilityLabel("\(task.title)、\(task.minutes)分、\(task.start.map { "時間外 \(clockText($0))" } ?? "未配置")")
                                .accessibilityIdentifier("inbox-\(task.title)")
                        }
                    }.padding(.vertical, 2)
                }
            }
        }.padding(.horizontal, 22).padding(.top, 15).padding(.bottom, 13)
            .background(returningToInbox ? tones[0] : paper)
            .background { GeometryReader { proxy in Color.clear.onAppear { inboxFrame = proxy.frame(in: .global) }.onChange(of: proxy.frame(in: .global)) { _, frame in inboxFrame = frame } } }
            .accessibilityElement(children: .contain).accessibilityIdentifier("inboxTray")
            .dropDestination(for: String.self) { values, _ in guard let raw = values.first, let id = UUID(uuidString: raw) else { return false }; plans.put(id, at: nil); return true }
    }
    private var bottomBar: some View {
        HStack {
            Button { plans.restore() } label: { Label("元に戻す", systemImage: "arrow.uturn.backward").font(.system(size: 11, weight: .medium)).frame(height: 42) }.disabled(plans.undo == nil).accessibilityIdentifier("undoButton")
            Spacer()
            if let id = selected, let task = plans.today.first(where: { $0.id == id }) {
                Button { plans.put(id, at: nil); selected = nil } label: { Image(systemName: "tray.and.arrow.down").frame(width: 38, height: 42) }.accessibilityLabel("未配置に戻す").accessibilityIdentifier("unplaceButton")
                Button { editing = task } label: { Image(systemName: "slider.horizontal.3").frame(width: 38, height: 42) }.accessibilityLabel("付箋を編集").accessibilityIdentifier("editButton")
            }
            Button { showNew = true } label: { Label("付箋をつくる", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 17).frame(height: 42).background(accent, in: Capsule()).foregroundStyle(.white) }.accessibilityIdentifier("newStickyButton")
        }.padding(.horizontal, 22).padding(.top, 9).padding(.bottom, 5).background(paper)
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
