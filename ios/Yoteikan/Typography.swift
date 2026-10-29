import SwiftUI
import UIKit

enum PlannerTypography {
    static let key = "planner.fontScale"
    static func clamp(_ value: Double) -> CGFloat { value.isFinite ? CGFloat(min(1.5, max(0.9, value))) : 1 }
    static var scale: CGFloat { clamp(UserDefaults.standard.object(forKey: key) as? Double ?? 1) }
    static func percent(_ value: Double) -> String { "\(Int((clamp(value) * 100).rounded()))%" }
    static func uiFont(for style: UIFont.TextStyle) -> UIFont {
        let font = UIFont.preferredFont(forTextStyle: style)
        return font.withSize(font.pointSize * scale)
    }
    static func points(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}
private struct PlannerScaledFont: ViewModifier {
    @AppStorage(PlannerTypography.key) private var requestedScale = 1.0
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight; self.design = design
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size * PlannerTypography.clamp(requestedScale), weight: weight, design: design))
    }
}
extension View {
    func plannerFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(PlannerScaledFont(size: size, weight: weight, design: design, relativeTo: .body))
    }
    func plannerFont(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(PlannerScaledFont(size: PlannerTypography.points(for: style), weight: weight, design: .default, relativeTo: style))
    }
}
