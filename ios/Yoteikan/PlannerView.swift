import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Paper treatment stays inside the card's bounds so even five-minute notes
/// retain their full touch target and never cover the next time slot.
private struct StickyPaper: View {
    let color: Color
    var selected = false
    var lifted = false
    var body: some View {
        GeometryReader { proxy in
            let fold = min(10, proxy.size.height * 0.18, proxy.size.width * 0.12)
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .top) {
                color
                LinearGradient(colors: [.black.opacity(0.055), .white.opacity(0.16), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: min(24, height * 0.45))
                Path { path in
                    path.move(to: CGPoint(x: width - fold, y: height))
                    path.addLine(to: CGPoint(x: width - fold, y: height - fold))
                    path.addLine(to: CGPoint(x: width, y: height - fold))
                    path.closeSubpath()
                }.fill(.white.opacity(0.38))
                Path { path in
                    path.move(to: CGPoint(x: width - fold, y: height))
                    path.addLine(to: CGPoint(x: width - fold, y: height - fold))
                    path.addLine(to: CGPoint(x: width, y: height - fold))
                }.stroke(.black.opacity(0.1), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(selected ? accent : .black.opacity(0.08), lineWidth: selected ? 2 : 0.5)
            }
            .shadow(color: .black.opacity(lifted ? 0.22 : 0.12), radius: lifted ? 7 : 1.5, x: 0, y: lifted ? 4 : 1)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private enum ScheduleMemoTarget: Identifiable {
    case sticky(UUID)
    case fixed(FixedEvent)
    var id: String {
        switch self {
        case .sticky(let id): return id.uuidString
        case .fixed(let event): return "fixed-" + event.id
        }
    }
}

private struct MemoPreviewContent {
    let title: String
    let time: String
    let memo: String
    init(target: ScheduleMemoTarget, stickies: [Sticky], drafts: [UUID: String]) {
        switch target {
        case .sticky(let id):
            let task = stickies.first { $0.id == id }
            title = task?.title ?? "付箋"
            time = task?.start.map { "\(clockText($0))〜\(clockText($0 + (task?.minutes ?? 0)))" } ?? "未配置"
            memo = drafts[id] ?? task?.memo ?? ""
        case .fixed(let event):
            title = event.title
            time = event.allDay ? "終日" : "\(clockText(event.start))〜\(clockText(event.end))"
            memo = event.memo
        }
    }
    var spoken: String { "\(title)、\(time)、\(memo.isEmpty ? "メモはありません" : memo)" }
}

/// A non-interactive, window-relative preview avoids clipping by timeline cards
/// and leaves the original recognizer in control until the finger is released.
private final class MemoPreviewPresenter {
    private var bubble: UIView?
    func hide() { bubble?.removeFromSuperview(); bubble = nil }
    func show(_ content: MemoPreviewContent, from source: UIView) {
        hide()
        guard let window = source.window else { return }
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground
        container.layer.cornerRadius = 14
        container.layer.borderWidth = 0.5
        container.layer.borderColor = UIColor.separator.cgColor
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.18
        container.layer.shadowRadius = 12
        container.layer.shadowOffset = CGSize(width: 0, height: 4)
        container.isUserInteractionEnabled = false
        container.accessibilityIdentifier = "memoPreview"
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 6
        for (text, style, lines) in [(content.title, UIFont.TextStyle.headline, 2),
                                     (content.time, .caption1, 1),
                                     (content.memo.isEmpty ? "メモはありません" : content.memo, .subheadline, 5)] {
            let label = UILabel()
            label.text = text; label.font = .preferredFont(forTextStyle: style)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = lines; label.lineBreakMode = .byTruncatingTail
            label.textColor = style == .caption1 ? .secondaryLabel : .label
            stack.addArrangedSubview(label)
        }
        container.addSubview(stack)
        let safe = window.bounds.inset(by: window.safeAreaInsets).insetBy(dx: 12, dy: 12)
        let width = min(300, safe.width)
        let size = stack.systemLayoutSizeFitting(CGSize(width: width - 28, height: 0),
                                                withHorizontalFittingPriority: .required,
                                                verticalFittingPriority: .fittingSizeLevel)
        let height = min(size.height + 28, safe.height)
        let anchor = source.convert(source.bounds, to: window)
        let above = anchor.minY - height - 12
        let y = above >= safe.minY ? above : min(safe.maxY - height, anchor.maxY + 12)
        container.frame = CGRect(x: min(max(safe.minX, anchor.midX - width / 2), safe.maxX - width),
                                 y: max(safe.minY, y), width: width, height: height)
        stack.frame = container.bounds.insetBy(dx: 14, dy: 14)
        stack.clipsToBounds = true
        window.addSubview(container)
        bubble = container
    }
    deinit { hide() }
}

private struct FullDayOverview: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    let hours: PlanningHours
    let stickies: [Sticky]
    let fixed: [FixedEvent]
    let colors: [StickyColor]
    @Binding var drafts: [UUID: String]
    private func preview(_ target: ScheduleMemoTarget) -> MemoPreviewContent { MemoPreviewContent(target: target, stickies: stickies, drafts: drafts) }
    var showsClose = true
    private struct Item: Identifiable {
        let id: String
        let title: String
        let start: Int
        let end: Int
        let tone: Int?
        let target: ScheduleMemoTarget
    }
    private var allItems: [Item] {
        let notes = stickies.compactMap { task -> Item? in
            guard let start = task.start else { return nil }
            return Item(id: task.id.uuidString, title: task.title, start: start, end: start + task.minutes, tone: task.tone, target: .sticky(task.id))
        }
        let events = fixed.filter { !$0.allDay }.map {
            Item(id: "fixed-" + $0.id, title: $0.title, start: $0.start, end: $0.end, tone: nil, target: .fixed($0))
        }
        return (notes + events).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }
    private var items: [Item] { allItems.filter { hours.overlaps(start: $0.start, end: $0.end) } }
    private var unplaced: [Sticky] { stickies.filter { $0.start == nil } }
    private func color(_ item: Item) -> Color {
        guard let tone = item.tone else { return Color(red: 0.89, green: 0.91, blue: 0.89) }
        return colors.first { $0.id == tone }?.color ?? tones[0]
    }
    private func textColor(_ item: Item) -> Color {
        guard let tone = item.tone else { return ink }
        return colors.first { $0.id == tone }?.textColor ?? ink
    }
    var body: some View {
        NavigationStack {
VStack(spacing: 8) {
    HStack(spacing: 4) {
        Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
            .accessibilityLabel("前の日").accessibilityIdentifier("overviewPreviousDay")
        Text(date, format: .dateTime.month().day().weekday(.abbreviated))
            .font(.subheadline.weight(.semibold)).accessibilityIdentifier("overviewDate")
        Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
            .accessibilityLabel("次の日").accessibilityIdentifier("overviewNextDay")
        Spacer(minLength: 0)
        Button("今日") { date = Date() }.frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("overviewToday")
    }.padding(.horizontal, 8)

                if !fixed.filter(\.allDay).isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(fixed.filter(\.allDay)) { event in
                            Label(event.title, systemImage: "sun.max").font(.caption).padding(6).background(.white, in: Capsule())
                                .overlay(MemoHold { preview(.fixed(event)) })
                                .accessibilityAction(named: "詳細メモ") { UIAccessibility.post(notification: .announcement, argument: preview(.fixed(event)).spoken) }
                        } }
                    }.padding(.horizontal, 12)
                }
                fittedTimeline
                Text("空き時間を省略・\(hours.label)・未配置 \(unplaced.count)枚\(allItems.count == items.count ? "" : "・時間外 \(allItems.count - items.count)件")")
                    .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 4)
            }.background(paper).foregroundStyle(ink)
                .navigationTitle("1日表示")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { if showsClose { ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.accessibilityIdentifier("closeFullDay")
                } } }
                .accessibilityElement(children: .contain).accessibilityIdentifier("fullDayOverview")
        }.tint(accent)
    }
    private func moveDay(_ offset: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: offset, to: date) { date = next }
    }
    private var fittedTimeline: some View {
        GeometryReader { geometry in
            let timelineItems = items.map { TimelineItem(id: $0.id, start: max(hours.start, $0.start), end: min(hours.end, $0.end)) }
            let folded = FoldedTimeline(items: timelineItems, start: hours.start, end: hours.end)
            let slots = PlannerMath.layout(timelineItems)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(folded.bands.indices, id: \.self) { index in
                        let band = folded.bands[index]
                        HStack(spacing: 6) {
                            Text(clockText(band.start)).font(.system(size: 10, design: .monospaced)).frame(width: 38, alignment: .trailing)
                            Rectangle().fill(ink.opacity(0.12)).frame(height: 1)
                        }.frame(height: 14).offset(y: band.y)
                        if !band.occupied {
                            Text("空き \(durationText(band.end - band.start))")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .frame(width: max(1, geometry.size.width - 52), height: band.height)
                                .offset(x: 48, y: band.y + 7)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(clockText(hours.end)).font(.system(size: 10, design: .monospaced)).frame(width: 38, alignment: .trailing)
                        Rectangle().fill(ink.opacity(0.12)).frame(height: 1)
                    }.frame(height: 14).offset(y: folded.height)
                    ForEach(items) { item in
                        let start = max(hours.start, item.start)
                        let slot = slots[item.id] ?? TimelineSlot(column: 0, columns: 1)
                        let width = max(1, geometry.size.width - 48) / CGFloat(slot.columns)
                        let cardHeight = folded.position(min(hours.end, item.end)) - folded.position(start) - 2
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium)).lineLimit(2)
                            .padding(.horizontal, 6).frame(width: max(1, width - 2), height: cardHeight, alignment: .leading)
                            .foregroundStyle(textColor(item))
                            .background {
                                if item.tone != nil { StickyPaper(color: color(item)) }
                                else { RoundedRectangle(cornerRadius: 5).fill(color(item)) }
                            }
                            .clipped().overlay(MemoHold { preview(item.target) })
                            .offset(x: 46 + width * CGFloat(slot.column), y: folded.position(start) + 7)
                            .accessibilityLabel("\(clockText(item.start))〜\(clockText(item.end))、\(item.title)")
                            .accessibilityIdentifier("fullDayBlock-\(item.title)")
                            .accessibilityHint("長押しして詳細メモを表示")
                            .accessibilityAction(named: "詳細メモ") { UIAccessibility.post(notification: .announcement, argument: preview(item.target).spoken) }
                    }
                    if items.isEmpty { Text("予定を配置するとここに表示されます").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).offset(y: folded.height + 28) }
                }.frame(height: max(folded.height + 60, geometry.size.height), alignment: .topLeading)
            }.accessibilityIdentifier("fullDayTimeline")
        }.padding(.horizontal, 12)
    }

}

private struct MemoHold: UIViewRepresentable {
    var content: () -> MemoPreviewContent
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.5
        view.addGestureRecognizer(press)
        #if targetEnvironment(macCatalyst)
        view.addGestureRecognizer(UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hover(_:))))
        #endif
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.content = content }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.presenter.hide() }
    final class Coordinator: NSObject {
        var content: (() -> MemoPreviewContent)?
        let presenter = MemoPreviewPresenter()
        #if targetEnvironment(macCatalyst)
        @objc func hover(_ gesture: UIHoverGestureRecognizer) {
            if gesture.state == .began, let source = gesture.view, let content = content?() { presenter.show(content, from: source) }
            else if gesture.state == .ended || gesture.state == .cancelled { presenter.hide() }
        }
        #endif
        @objc func press(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began, let source = gesture.view, let content = content?() {
                presenter.show(content, from: source)
            } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                presenter.hide()
            }
        }
    }
}

private struct TimelinePinch: UIViewRepresentable {
    var changed: (CGFloat, CGFloat) -> Void
    var ended: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.changed = changed
        context.coordinator.ended = ended
        DispatchQueue.main.async { context.coordinator.install(from: view) }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var changed: ((CGFloat, CGFloat) -> Void)?
        var ended: (() -> Void)?
        weak var scroll: UIScrollView?
        var originalTouches = Int.max
        var sizeObservation: NSKeyValueObservation?
        var startHeight: CGFloat = 1
        var anchorContentY: CGFloat = 0
        var anchorViewportY: CGFloat = 0
        var tracking = false
        var generation = UUID()
        lazy var recognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        func install(from view: UIView) {
            var ancestor = view.superview
            while let current = ancestor {
                if let target = current as? UIScrollView {
                    guard scroll !== target else { return }
                    detach()
                    scroll = target
                    originalTouches = target.panGestureRecognizer.maximumNumberOfTouches
                    target.panGestureRecognizer.maximumNumberOfTouches = 1
                    recognizer.delegate = self
                    target.addGestureRecognizer(recognizer)
                    sizeObservation = target.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                        self?.restoreAnchor()
                    }
                    return
                }
                ancestor = current.superview
            }
        }
        func detach() {
            sizeObservation = nil
            tracking = false
            scroll?.removeGestureRecognizer(recognizer)
            scroll?.panGestureRecognizer.maximumNumberOfTouches = originalTouches
            scroll = nil
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard let scroll else { return }
            switch gesture.state {
            case .began:
                generation = UUID()
                tracking = true
                // The timeline adds 12 points above and 18 below its scaled content.
                startHeight = max(1, scroll.contentSize.height - 30)
                anchorViewportY = gesture.location(in: scroll).y - scroll.bounds.minY
                anchorContentY = scroll.contentOffset.y + anchorViewportY - 12
                scroll.setContentOffset(scroll.contentOffset, animated: false)
                let y = anchorViewportY / max(1, scroll.bounds.height)
                changed?(gesture.scale, y)
            case .changed:
                anchorViewportY = gesture.location(in: scroll).y - scroll.bounds.minY
                let y = (gesture.location(in: scroll).y - scroll.bounds.minY) / max(1, scroll.bounds.height)
                changed?(gesture.scale, y)
                restoreAnchor()
            case .ended, .cancelled, .failed:
                ended?()
                let current = generation
                // Allow the final SwiftUI layout to settle before releasing the anchor.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.generation == current else { return }
                    self.restoreAnchor(); self.tracking = false
                }
            default: break
            }
        }
        private func restoreAnchor() {
            guard tracking, let scroll else { return }
            let ratio = max(1, scroll.contentSize.height - 30) / startHeight
            let proposed = (anchorContentY * ratio) + 12 - anchorViewportY
            let minimum = -scroll.adjustedContentInset.top
            let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let offset = min(maximum, max(minimum, proposed))
            if abs(scroll.contentOffset.y - offset) > 0.25 {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

private struct StickyTouch: UIViewRepresentable {
    var preview: () -> MemoPreviewContent
    var tapped: () -> Void
    var changed: (CGFloat, CGPoint) -> Void
    var ended: (CGFloat, CGPoint) -> Void
    var cancelled: () -> Void
    var menuRequested: (() -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        #if targetEnvironment(macCatalyst)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.mouseDrag(_:)))
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hover(_:))))
        #endif
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0.3
        press.allowableMovement = 10
        press.numberOfTouchesRequired = 1
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        tap.require(toFail: press)
        view.addGestureRecognizer(press)
        view.addGestureRecognizer(tap)
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.actions = self }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.cancelPending(); coordinator.presenter.hide() }
    final class Coordinator: NSObject {
        var actions: StickyTouch?
        let presenter = MemoPreviewPresenter()
        var origin = CGPoint.zero
        var dragged = false
        var consumed = false
        var token = UUID()
        var pending: DispatchWorkItem?
        func cancelPending() { pending?.cancel(); pending = nil; token = UUID() }
        @objc func tap() { actions?.tapped() }
        #if targetEnvironment(macCatalyst)
        @objc func hover(_ gesture: UIHoverGestureRecognizer) {
            if gesture.state == .began, let source = gesture.view, let content = actions?.preview() { presenter.show(content, from: source) }
            else if gesture.state == .ended || gesture.state == .cancelled { presenter.hide() }
        }
        @objc func mouseDrag(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: nil)
            switch gesture.state {
            case .began: cancelPending(); presenter.hide(); origin = CGPoint(x: point.x, y: point.y - gesture.translation(in: nil).y); actions?.changed(gesture.translation(in: nil).y, point)
            case .changed: actions?.changed(point.y - origin.y, point)
            case .ended: actions?.ended(point.y - origin.y, point)
            case .cancelled, .failed: actions?.cancelled()
            default: break
            }
        }
        #endif

        @objc func press(_ gesture: UILongPressGestureRecognizer) {
            let point = gesture.location(in: nil)
            switch gesture.state {
            case .began:
                cancelPending()
                origin = point; dragged = false; consumed = false
                actions?.changed(0, point)
                let current = token
                let source = gesture.view
                let work = DispatchWorkItem { [weak self, weak source] in
                    guard let self, self.token == current, !self.dragged, !self.consumed else { return }
                    self.consumed = true; self.pending = nil
                    self.actions?.cancelled()
                    if let source, let content = self.actions?.preview() { self.presenter.show(content, from: source) }
                }
                pending = work
                // Dragging soon after the hold keeps the existing move gesture.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            case .changed:
                guard !consumed else { return }
                if hypot(point.x - origin.x, point.y - origin.y) > 8 { dragged = true; cancelPending() }
                if dragged { actions?.changed(point.y - origin.y, point) }
            case .ended:
                cancelPending(); presenter.hide()
                guard !consumed else { actions?.menuRequested?(); return }
                if dragged || hypot(point.x - origin.x, point.y - origin.y) > 8 { actions?.ended(point.y - origin.y, point) }
                else { actions?.cancelled() }
            case .cancelled, .failed: cancelPending(); presenter.hide(); actions?.cancelled()
            default: break
            }
        }
    }

}

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
    @State private var showNew = false
    @State private var editing: Sticky?
    @State private var selected: UUID?
    @State private var copyID: UUID?
    @State private var showCopyMenu = false
    @State private var folded = false
    @State private var overview = false
    @State private var zoomFactor: CGFloat = 1
    @State private var pinchBase: CGFloat?
    @State private var pinchMinute: CGFloat?
    @State private var pinchAnchor = UnitPoint.center
    @State private var minuteAtTop: CGFloat = 480
    @State private var visibleHour: Int?
    @State private var positionedTimeline = false
    @State private var zoomAnchor = 8
    @State private var viewportTop: CGFloat = 0
    @State private var viewportFrame = CGRect.zero
    private let zoomSteps: [CGFloat] = [1, 2, 4, 8]
    @State private var dropActive = false
    @State private var moving: UUID?
    @State private var shift: CGFloat = 0
    @State private var stretching: UUID?
    @State private var stretch: CGFloat = 0
    @State private var viewportHeight: CGFloat = 350
    @State private var inboxFrame = CGRect.zero
    @State private var returningToInbox = false
    @AppStorage("planner.sidebarLeading") private var sidebarLeading = false
    @State private var sideShowsDetails = false
    @State private var memoDrafts: [UUID: String] = [:]
    @State private var tab = 0
    @FocusState private var memoFocused: Bool
    private var selectedTask: Sticky? { plans.today.first { $0.id == selected } }
    private var scale: CGFloat { overview ? max(0.15, (viewportHeight - 32) / CGFloat(plans.hours.totalMinutes)) : 1.55 * zoomFactor }
    private var fixed: [FixedEvent] {
        if plans.demo, dayKey(plans.date) == dayKey(Date()) {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--short-events-test") {
                return [FixedEvent(id: "short1", title: "会議5分", start: 495, end: 500), FixedEvent(id: "short2", title: "連絡5分", start: 500, end: 505)]
            }
            #endif
            return [FixedEvent(id: "demo1", title: "チームミーティング", start: 600, end: 660, memo: "進捗と次の作業を確認"), FixedEvent(id: "demo2", title: "打ち合わせ", start: 840, end: 900)]
        }
        return calendar.events
    }
    private func preview(_ target: ScheduleMemoTarget) -> MemoPreviewContent { MemoPreviewContent(target: target, stickies: plans.plan.stickies, drafts: memoDrafts) }
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
        nativeTabs
            #if targetEnvironment(macCatalyst)
            .focusedSceneValue(\.macPlannerActions, MacPlannerActions(
                create: { showNew = true }, selectTab: { tab = $0 },
                changeDay: { changeDay($0) }, today: { plans.date = Date() },
                zoom: { factor in setZoom(min(8, max(1, zoomFactor * factor))) }
            ))
            .background(MacWindowSetup())
            #endif
            .onChange(of: tab) { _, _ in memoFocused = false }
        .sheet(isPresented: $showPresets) { PresetsView() }
        .sheet(isPresented: $showCalendar) { CalendarSettingsView() }
        .sheet(isPresented: $showNew) { StickyEditor(task: Sticky(title: "", minutes: 30, day: dayKey(plans.date)), isNew: true) }
        .sheet(item: $editing) { StickyEditor(task: $0, isNew: false) }
        .onChange(of: plans.date) { _, value in calendar.refresh(date: value); selected = nil }
        .onChange(of: phase) { _, value in if value == .active { plans.refreshDay(); calendar.refresh(date: plans.date) } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in plans.refreshDay(); calendar.refresh(date: plans.date) }
        .confirmationDialog("付箋の操作", isPresented: $showCopyMenu, titleVisibility: .hidden) {
            Button("コピー") { if let id = copyID { copySticky(id) } }.accessibilityIdentifier("copyStickyAction")
            Button("キャンセル", role: .cancel) { }
        }
        .alert("付箋を配置できません", isPresented: Binding(get: { plans.notice != nil }, set: { if !$0 { plans.notice = nil } })) {
            Button("OK") { plans.notice = nil }
        } message: { Text(plans.notice ?? "") }
    }
    private var plannerContent: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
        VStack(spacing: 0) {
            HStack(spacing: 0) { dateBar }.padding(.horizontal, 6)
            stats
            if !calendar.connected && !plans.demo {
                Button { showCalendar = true } label: {
                    HStack(spacing: 8) { Image(systemName: "calendar.badge.plus"); Text("カレンダーを接続").font(.system(size: 11, weight: .medium)); Spacer(); Image(systemName: "chevron.right") }.padding(.horizontal, 12).padding(.vertical, 5).foregroundStyle(accent)
                }.accessibilityIdentifier("calendarConnectBanner")
            }
            if !fixed.filter(\.allDay).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(fixed.filter(\.allDay)) { event in Label(event.title, systemImage: "sun.max").font(.caption2).padding(7).background(.white.opacity(0.6), in: Capsule()).overlay(MemoHold { preview(.fixed(event)) }).accessibilityAction(named: "詳細メモ") { UIAccessibility.post(notification: .announcement, argument: preview(.fixed(event)).spoken) } } }.padding(.horizontal, 20) }
            }
            let zones = sidebarLeading ? (wide && !sideShowsDetails ? ["side", "memo", "schedule"] : ["side", "schedule"]) : (wide && !sideShowsDetails ? ["schedule", "memo", "side"] : ["schedule", "side"])
            HStack(spacing: 0) {
                ForEach(zones, id: \.self) { zone in
                    if zone == "schedule" {
                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                Button {
                                    moving = nil; stretching = nil; shift = 0; stretch = 0
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) { folded.toggle() }
                                } label: {
                                    Label(folded ? "広げる" : "空きをたたむ", systemImage: folded ? "arrow.up.and.down" : "arrow.down.and.line.horizontal.and.arrow.up")
                                        .font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(minHeight: 28)
                                }.buttonStyle(.plain).foregroundStyle(accent)
                                    .accessibilityIdentifier("foldPlanner")
                                    .accessibilityValue(folded ? "折りたたみ中" : "通常表示")
                            }
                            timeline
                        }
                            .accessibilityElement(children: .contain).accessibilityIdentifier("scheduleZone")
                    } else if zone == "memo" {
                        VStack(spacing: 0) { zoneTitle("詳細メモ"); memoPane }
                            .frame(width: geometry.size.width * 0.28)
                            .accessibilityElement(children: .contain).accessibilityIdentifier("memoZone")
                    } else {
                        sideZone.frame(width: wide ? geometry.size.width * 0.25 : max(124, geometry.size.width * 0.34))
                    }
                    if zone != zones.last { Divider() }
                }
            }

        }
        }
        .background(paper).foregroundStyle(ink)
    }
    @ViewBuilder private var nativeTabs: some View {
        if #available(iOS 26.0, *) { tabs.tabBarMinimizeBehavior(.never) }
        else { tabs }
    }
    private var tabs: some View {
        TabView(selection: $tab) {
            plannerContent.tabItem { Label("計画", systemImage: "calendar.day.timeline.left") }.tag(0)
            FullDayOverview(date: $plans.date, hours: plans.hours, stickies: plans.today, fixed: fixed, colors: plans.plan.colors, drafts: $memoDrafts, showsClose: false)
                .tabItem { Label("1日表示", systemImage: "rectangle.expand.vertical") }.tag(1)
            PlannerSettingsTab(onFinished: { tab = 0 }).tabItem { Label("設定", systemImage: "gearshape") }.tag(2)
        }.tint(accent)
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
                            Button("未配置に戻す") { plans.put(task.id, at: nil); sideShowsDetails = false }.font(.system(size: 11))
                                .accessibilityIdentifier("unplaceButton")
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
        timeBar("空き時間", minutes: plans.hours.totalMinutes - occupied, color: accent, identifier: "freeTimeBar")
            .padding(.horizontal, 12).padding(.vertical, 4)
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
    private func cardHeight(_ minutes: Int) -> CGFloat {
        let slot = CGFloat(minutes) * scale
        return max(0, slot - min(overview ? 1 : 4, slot * 0.25))
    }
    private func setZoom(_ factor: CGFloat) {
        pinchMinute = nil
        zoomAnchor = selectedTask?.start.map { $0 / 60 } ?? visibleHour ?? initialHour
        zoomFactor = factor
    }
    private func updatePinch(_ magnification: CGFloat, anchor: CGFloat) {
        if overview && magnification <= 1 { return }
        if pinchBase == nil {
            pinchBase = scale / 1.55
            pinchAnchor = UnitPoint(x: 0.5, y: min(1, max(0, anchor)))
            pinchMinute = min(CGFloat(plans.hours.end), max(CGFloat(plans.hours.start), minuteAtTop + pinchAnchor.y * viewportHeight / scale))
            moving = nil; stretching = nil; shift = 0; stretch = 0
            overview = false
        }
        zoomFactor = min(8, max(1, (pinchBase ?? zoomFactor) * magnification))
    }
    @ViewBuilder private func pinchMarker(_ hour: Int) -> some View {
        if let minute = pinchMinute, Int(minute / 60) == hour {
            let offset: CGFloat = (minute - CGFloat(hour * 60)) * scale
            VStack(spacing: 0) {
                Color.clear.frame(height: offset)
                Color.clear.frame(height: 1).id("pinch-anchor")
                Spacer(minLength: 0)
            }.frame(width: 1).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    private func hourRow(_ hour: Int) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text(String(format: "%02d:00", hour)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(ink.opacity(0.55)).frame(width: 34, alignment: .trailing)
                Rectangle().fill(ink.opacity(0.09)).frame(height: 1)
            }
            if !overview && zoomFactor >= 4 && hour < plans.hours.end / 60 {
                ForEach(1..<12) { step in
                    HStack(spacing: 6) {
                        Text(String(format: ":%02d", step * 5)).font(.system(size: 8, design: .monospaced)).frame(width: 34, alignment: .trailing)
                        Rectangle().frame(height: 0.5)
                    }.foregroundStyle(ink.opacity(0.22)).offset(y: CGFloat(step * 5) * scale)
                }
            }
        }.frame(height: 60 * scale, alignment: .top).id("hour-\(hour)")
            .background { GeometryReader { proxy in Color.clear.preference(key: HourPositions.self, value: [hour: proxy.frame(in: .global).minY]) } }
            .overlay(alignment: .topLeading) { pinchMarker(hour) }
    }
    private var foldedLayout: FoldedTimeline {
        FoldedTimeline(items: placed.map { TimelineItem(id: $0.id.uuidString, start: $0.start!, end: $0.start! + $0.minutes) }
                       + visibleFixed.map { TimelineItem(id: "fixed-" + $0.id, start: $0.start, end: $0.end) },
                       start: plans.hours.start, end: plans.hours.end)
    }
    private func timelineY(_ minute: Int) -> CGFloat {
        folded ? foldedLayout.position(minute) : CGFloat(minute - plans.hours.start) * scale
    }
    private func timelineMinute(_ y: CGFloat) -> CGFloat {
        folded ? foldedLayout.minute(at: y) : CGFloat(plans.hours.start) + y / scale
    }
    private func movedStart(_ task: Sticky, delta: CGFloat) -> Int {
        PlannerMath.start(PlannerMath.snap(Double(timelineMinute(timelineY(task.start!) + delta))),
                          duration: task.minutes, from: plans.hours.start, to: plans.hours.end)
    }
    private func resizedDuration(_ task: Sticky, delta: CGFloat) -> Int {
        PlannerMath.duration(PlannerMath.snap(Double(timelineMinute(timelineY(task.start! + task.minutes) + delta))) - task.start!,
                             start: task.start!, to: plans.hours.end)
    }
    private func placedCard(_ task: Sticky, availableWidth: CGFloat) -> some View {
        let visibleStart = max(task.start!, plans.hours.start)
        let visibleEnd = min(task.start! + task.minutes, plans.hours.end)
        let collision = conflicts(task)
        let slot = slots[task.id.uuidString] ?? TimelineSlot(column: 0, columns: 1)
        let slotCount = slot.columns
        let width = (availableWidth - 42) / CGFloat(slotCount)
        let height = max(0, timelineY(visibleEnd) - timelineY(visibleStart) - (folded ? 2 : min(4, CGFloat(visibleEnd - visibleStart) * scale * 0.25)) + (stretching == task.id ? stretch : 0))
        return taskCard(task, compact: overview || slotCount > 1, height: height)
            .frame(width: width - 3, height: height)
            .overlay(StickyTouch(
                preview: { preview(.sticky(task.id)) },
                tapped: { if selected == task.id { editing = task } else { selected = task.id } },
                changed: { delta, point in updateMove(task, delta: delta, location: point) },
                ended: { delta, point in finishMove(task, delta: delta, location: point) },
                cancelled: { moving = nil; shift = 0; returningToInbox = false },
                menuRequested: { copyID = task.id; showCopyMenu = true }
            ))
            .overlay { if collision { RoundedRectangle(cornerRadius: 9).stroke(.orange, lineWidth: 1.5).allowsHitTesting(false) } }
            .overlay(alignment: .bottom) { if !overview && (height >= 54 || stretching == task.id) { resizeHandle(task) } }
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if selected == task.id && !overview && height >= 32 { moveHandle(task).padding(3) }
            }
            .clipped()
            .accessibilityAction(named: "詳細メモ") { UIAccessibility.post(notification: .announcement, argument: preview(.sticky(task.id)).spoken) }
            .overlay(alignment: .top) {
                if moving == task.id && !returningToInbox {
                    let start = movedStart(task, delta: shift)
                    Text("\(clockText(start)) – \(clockText(start + task.minutes))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(ink, in: Capsule()).foregroundStyle(.white)
                        .offset(y: -29).allowsHitTesting(false)
                }
            }
            .offset(x: 40 + width * CGFloat(slot.column), y: timelineY(visibleStart) + 2 + (moving == task.id ? shift : 0))
            .zIndex(moving == task.id || stretching == task.id ? 5 : selected == task.id ? 3 : 1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("task-\(task.title)")
            .accessibilityValue("\(clockText(task.start!))|\(task.minutes)")
            .accessibilityAction(named: "コピー") { copySticky(task.id) }
            .accessibilityHint(collision ? "ほかの予定と重なっています" : "")
    }
    private var timeline: some View {
        Group {
            if folded { foldedPlanningTimeline }
            else { expandedTimeline }
        }
    }
    private var foldedPlanningTimeline: some View {
        GeometryReader { geometry in
            let layout = foldedLayout
            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(layout.bands.indices, id: \.self) { index in
                        let band = layout.bands[index]
                        HStack(spacing: 6) {
                            Text(clockText(band.start)).font(.system(size: 9, design: .monospaced)).frame(width: 34, alignment: .trailing)
                            Rectangle().fill(ink.opacity(0.12)).frame(height: 1)
                        }.frame(height: 12).offset(y: band.y)
                        if !band.occupied {
                            Text("空き \(durationText(band.end - band.start))").font(.system(size: 9)).foregroundStyle(.secondary)
                                .frame(width: max(1, geometry.size.width - 42), height: band.height)
                                .offset(x: 40, y: band.y + 6).allowsHitTesting(false)
                        }
                    }
                    Text(clockText(plans.hours.end)).font(.system(size: 9, design: .monospaced))
                        .frame(width: 34, alignment: .trailing).offset(y: layout.height)
                    ForEach(visibleFixed) { event in
                        let start = max(plans.hours.start, event.start)
                        let slot = slots["fixed-" + event.id] ?? TimelineSlot(column: 0, columns: 1)
                        let width = (geometry.size.width - 42) / CGFloat(slot.columns)
                        let height = timelineY(min(event.end, plans.hours.end)) - timelineY(start) - 2
                        fixedCard(event, height: height).frame(width: width - 3, height: height).clipped()
                            .overlay(MemoHold { preview(.fixed(event)) })
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(event.title)、\(clockText(event.start))から\(clockText(event.end))、カレンダーの固定予定")
                            .accessibilityIdentifier("fixed-\(event.title)")
                            .accessibilityAction(named: "詳細メモ") { UIAccessibility.post(notification: .announcement, argument: preview(.fixed(event)).spoken) }
                            .offset(x: 40 + width * CGFloat(slot.column), y: timelineY(start) + 2)
                    }
                    ForEach(placed) { task in placedCard(task, availableWidth: geometry.size.width) }
                }
                .frame(width: geometry.size.width, height: max(layout.height + 18, geometry.size.height), alignment: .topLeading)
                .background(Color.white.opacity(0.01))
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { values, point in
                    guard let raw = values.first, let id = UUID(uuidString: raw), plans.today.contains(where: { $0.id == id }) else { return false }
                    plans.put(id, at: PlannerMath.snap(Double(timelineMinute(point.y)))); selected = id; return true
                } isTargeted: { dropActive = $0 }
                .background(dropActive ? accent.opacity(0.05) : .clear)
                .padding(.top, 12)
            }.scrollDisabled(moving != nil || stretching != nil)
                .accessibilityIdentifier("foldedPlannerTimeline")
        }.background(.white.opacity(0.62))
    }
    private var expandedTimeline: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                        ForEach((plans.hours.start / 60)...(plans.hours.end / 60), id: \.self) { hour in
                            hourRow(hour)
                        }
                        }.contentShape(Rectangle()).simultaneousGesture(daySwipeGesture)
                        ForEach(visibleFixed) { event in
                            let start = max(plans.hours.start, event.start)
                            let slot = slots["fixed-" + event.id] ?? TimelineSlot(column: 0, columns: 1)
                            let width = (geometry.size.width - 42) / CGFloat(slot.columns)
                            let height = cardHeight(min(event.end, plans.hours.end) - start)
                            fixedCard(event, height: height).frame(width: width - 3, height: height).clipped()
                                .overlay(MemoHold { preview(.fixed(event)) })
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(event.title)、\(clockText(event.start))から\(clockText(event.end))、カレンダーの固定予定")
                                .accessibilityIdentifier("fixed-\(event.title)")
                                .accessibilityAction(named: "詳細メモ") { UIAccessibility.post(notification: .announcement, argument: preview(.fixed(event)).spoken) }
                                .offset(x: 40 + width * CGFloat(slot.column), y: CGFloat(start - plans.hours.start) * scale + 2)
                        }
                        ForEach(placed) { task in
                            placedCard(task, availableWidth: geometry.size.width)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { values, location in
                        guard let raw = values.first, let id = UUID(uuidString: raw), plans.today.contains(where: { $0.id == id }) else { return false }
                        plans.put(id, at: plans.hours.start + PlannerMath.snap(Double(location.y / scale))); selected = id; return true
                    } isTargeted: { dropActive = $0 }
                    .background(dropActive ? accent.opacity(0.05) : Color.clear)
                    .background(TimelinePinch(changed: updatePinch, ended: {
                        Task { @MainActor in await Task.yield(); pinchBase = nil }
                    }))
                }.frame(height: CGFloat(plans.hours.end - plans.hours.start) * scale + 18).padding(.top, 12).padding(.horizontal, 5)
            }.scrollDisabled(moving != nil || stretching != nil)
                .coordinateSpace(name: "timelineViewport").accessibilityIdentifier("timeline")
                .onPreferenceChange(HourPositions.self) { positions in
                    visibleHour = positions.filter { $0.value <= viewportTop + 16 }.max(by: { $0.value < $1.value })?.key ?? initialHour
                    if let hour = visibleHour, let y = positions[hour] {
                        minuteAtTop = CGFloat(hour * 60) + (viewportTop - y) / scale
                    }
                }
                .task {
                    guard !positionedTimeline else { return }
                    positionedTimeline = true
                    await Task.yield(); reader.scrollTo("hour-\(initialHour)", anchor: .top)
                }
                .onChange(of: zoomFactor) { _, _ in
                    guard pinchMinute == nil else { return }
                    reader.scrollTo("hour-\(zoomAnchor)", anchor: .top)
                }
                .onChange(of: overview) { _, value in
                    if pinchBase == nil { reader.scrollTo("hour-\(value ? plans.hours.start / 60 : initialHour)", anchor: .top) }
                }
                .onChange(of: plans.date) { _, _ in reader.scrollTo("hour-\(overview ? plans.hours.start / 60 : initialHour)", anchor: .top) }
                .onChange(of: plans.hours) { _, _ in
                    selected = nil; moving = nil; stretching = nil; shift = 0; stretch = 0
                    reader.scrollTo("hour-\(overview ? plans.hours.start / 60 : initialHour)", anchor: .top)
                }
        }
        .background(.white.opacity(0.62))
        .overlay {
            Color.clear.accessibilityElement(children: .ignore)
                .accessibilityLabel("時間割の拡大率")
                .accessibilityValue("\(Double(zoomFactor).formatted(.number.precision(.fractionLength(0...1))))倍")
                .accessibilityIdentifier("timelineZoomSurface")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: overview = false; setZoom(zoomSteps.first(where: { $0 > zoomFactor + 0.001 }) ?? 8)
                    case .decrement: if !overview { setZoom(zoomSteps.last(where: { $0 < zoomFactor - 0.001 }) ?? 1) }
                    @unknown default: break
                    }
                }
                .padding(24).allowsHitTesting(false)
        }
        .background { GeometryReader { proxy in Color.clear.onAppear { viewportHeight = proxy.size.height; viewportFrame = proxy.frame(in: .global); viewportTop = viewportFrame.minY }.onChange(of: proxy.frame(in: .global)) { _, frame in viewportHeight = frame.height; viewportFrame = frame; viewportTop = frame.minY } } }
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.06)).frame(height: 1) }
    }
    private func fixedCard(_ event: FixedEvent, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: overview ? 0 : 5) {
            if height < 44 {
                if height >= 14 { Text(event.title).font(.system(size: folded ? 12 : 10, weight: .medium)).lineLimit(folded ? 2 : 1) }
            } else if overview { Text(event.title).font(.system(size: 7, weight: .medium)).lineLimit(1) }
            else { HStack { Image(systemName: "lock.fill").font(.system(size: 9)); Text("\(clockText(event.start)) – \(clockText(event.end))").font(.system(size: 10, weight: .medium)); Spacer(minLength: 0) }.foregroundStyle(ink.opacity(0.55))
            if !overview { Text(event.title).font(.system(size: 13, weight: .medium)).lineLimit(2) }
            Spacer(minLength: 0)
            }
        }.padding(height < 44 ? min(height / 2, 2) : 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(red: 0.89, green: 0.91, blue: 0.89), in: RoundedRectangle(cornerRadius: 9)).overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.25)).frame(width: 3).padding(.vertical, 9) }.clipped()
    }
    private func taskCard(_ task: Sticky, compact: Bool, height: CGFloat) -> some View {
        let textColor = plans.paletteColor(for: task.tone).textColor
        let start = moving == task.id ? movedStart(task, delta: shift) : (task.start ?? 0)
        let duration = stretching == task.id ? resizedDuration(task, delta: stretch) : task.minutes
        return VStack(alignment: .leading, spacing: 4) {
            if height < 44 {
                if height >= 14 { Text(task.title).font(.system(size: folded ? 12 : 10, weight: .semibold)).lineLimit(folded ? 2 : 1) }
            } else if overview {
                if duration >= 45 { Text(task.title).font(.system(size: 7, weight: .semibold)).lineLimit(1) }
            } else {
            if !compact { Text("\(clockText(start)) – \(clockText(start + duration))").font(.system(size: 10, weight: .medium)).foregroundStyle(textColor.opacity(0.8)) }
            HStack(spacing: 4) { Text(task.title).font(.system(size: compact ? 10 : 12, weight: .semibold)).lineLimit(2); Spacer(minLength: 0); if compact { Text("\(duration)分").font(.system(size: 9)) } }.padding(.trailing, selected == task.id ? 29 : 0)
            Spacer(minLength: 0)
            }
        }.padding(.horizontal, overview ? 3 : 7).padding(.top, height < 44 ? 1 : (compact ? 5 : 7)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(textColor)
            .background(StickyPaper(color: plans.paletteColor(for: task.tone).color,
                                    selected: selected == task.id, lifted: moving == task.id))
            .accessibilityLabel("\(task.title)、\(clockText(start))から\(duration)分")
    }
    private func resizeHandle(_ task: Sticky) -> some View {
        ZStack { Color.clear; Capsule().fill(plans.paletteColor(for: task.tone).textColor.opacity(selected == task.id ? 0.6 : 0.35)).frame(width: 24, height: 3) }
            .frame(width: 44, height: 22).contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
                guard pinchBase == nil else { return }
                selected = task.id; stretching = task.id
                let newDuration = resizedDuration(task, delta: value.translation.height)
                stretch = timelineY(task.start! + newDuration) - timelineY(task.start! + task.minutes)
            }.onEnded { value in
                guard pinchBase == nil, stretching == task.id else { return }
                plans.resize(task.id, minutes: resizedDuration(task, delta: value.translation.height)); stretching = nil; stretch = 0
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
        guard pinchBase == nil, let start = task.start else { return }
        selected = task.id; moving = task.id
        returningToInbox = inboxFrame.contains(location)
        let newStart = movedStart(task, delta: delta)
        shift = timelineY(newStart) - timelineY(start)
    }
    private func finishMove(_ task: Sticky, delta: CGFloat, location: CGPoint) {
        defer { moving = nil; shift = 0; returningToInbox = false }
        guard pinchBase == nil, moving == task.id, let start = task.start else { return }
        if inboxFrame.contains(location) { plans.put(task.id, at: nil); selected = nil; sideShowsDetails = false }
        else { plans.move(task.id, start: movedStart(task, delta: delta)) }
    }
    private func copySticky(_ id: UUID) {
        if let copy = plans.duplicate(id) { selected = copy; sideShowsDetails = false }
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
                                .background(StickyPaper(color: plans.paletteColor(for: task.tone).color,
                                                        selected: selected == task.id))
                                .foregroundStyle(plans.paletteColor(for: task.tone).textColor)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = task.id; sideShowsDetails = true }.draggable(task.id.uuidString)
                                .accessibilityElement(children: .ignore).accessibilityLabel("\(task.title)、\(task.minutes)分、\(task.start.map { "時間外 \(clockText($0))" } ?? "未配置")")
                                .contextMenu { Button("コピー") { copySticky(task.id) }.accessibilityIdentifier("copyStickyAction") }
                                .accessibilityAction(named: "コピー") { copySticky(task.id) }
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

#if targetEnvironment(macCatalyst)
private struct MacWindowSetup: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { let view = UIView(); view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { view.window?.windowScene?.sizeRestrictions?.minimumSize = CGSize(width: 780, height: 560) }
    }
}
#endif
