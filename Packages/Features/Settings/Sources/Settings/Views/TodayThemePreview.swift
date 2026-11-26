import SwiftUI
import VikuDesignSystem

/// A static illustration of Today that scales to the width of its tile.
struct TodayThemePreview: View {
    let palette: VikuPalette
    private let artworkSize = CGSize(width: 112, height: 98)
    private let topInset: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            var context = context
            let scale = size.width / artworkSize.width
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: topInset)
            drawHeader(in: context)
            drawTasks(in: context)
            drawNavigation(in: context)
        }
        .background(palette.pageBackground)
        .aspectRatio(CGSize(width: artworkSize.width, height: artworkSize.height + topInset), contentMode: .fit)
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
    }

    private func drawHeader(in context: GraphicsContext) {
        var titleContext = context
        titleContext.translateBy(x: 10, y: 8)
        titleContext.scaleBy(x: 0.8, y: 0.8)
        titleContext.draw(
            Text("Today", bundle: .module)
                .font(VikuFont.caption2.weight(.bold))
                .foregroundStyle(palette.textPrimary),
            at: .zero,
            anchor: .topLeading,
        )
        context.fillPill(10, 22, 16.5, 6, palette.brand)
        context.fillPill(29.5, 22, 11, 6, palette.fieldBackground)
        context.fillPill(43.5, 22, 8.25, 6, palette.fieldBackground)
    }

    private func drawTasks(in context: GraphicsContext) {
        let titleWidths: [CGFloat] = [47, 33, 40]
        for (index, titleWidth) in titleWidths.enumerated() {
            let top = 33 + CGFloat(index) * 12
            let row = CGRect(x: 10, y: top, width: 92, height: 11)
            context.fill(Path(roundedRect: row, cornerRadius: 3), with: .color(palette.cardBackground))
            let isDone = index == titleWidths.count - 1
            drawCheckbox(at: row.midY, isDone: isDone, in: context)
            let showsLabel = index == 0
            let titleY = showsLabel ? top + 2.5 : row.midY - 1.25
            context.fillPill(23, titleY, titleWidth, 2.5, palette.textPrimary.opacity(isDone ? 0.17 : 0.25))
            if showsLabel {
                context.fillPill(23, top + 6.5, 14, 2.5, VikuColor.AccentTint.amber.color.opacity(0.4))
            }
        }
    }

    private func drawCheckbox(at centerY: CGFloat, isDone: Bool, in context: GraphicsContext) {
        let circle = Path(ellipseIn: CGRect(x: 13, y: centerY - 3, width: 6, height: 6))
        if isDone {
            context.fill(circle, with: .color(palette.brand))
            let checkmark = Path { path in
                path.move(to: CGPoint(x: 14.5, y: centerY))
                path.addLine(to: CGPoint(x: 15.5, y: centerY + 1))
                path.addLine(to: CGPoint(x: 17.5, y: centerY - 1))
            }
            context.stroke(checkmark, with: .color(palette.brandForeground), style: StrokeStyle(
                lineWidth: 0.8, lineCap: .round, lineJoin: .round,
            ))
        } else {
            context.stroke(circle, with: .color(palette.brand), lineWidth: 0.8)
        }
    }

    private func drawNavigation(in context: GraphicsContext) {
        context.fillPill(89, 70, 13, 13, palette.brand)
        context.fillPill(93, 76, 5, 1, palette.brandForeground)
        context.fillPill(95, 74, 1, 5, palette.brandForeground)

        context.fillPill(10, 85, 92, 10, palette.cardBackground)
        let tabCenters: [CGFloat] = [21.5, 44.5, 67.5, 90.5]
        for (index, center) in tabCenters.enumerated() {
            let color = index == 0 ? palette.brand : palette.textSecondary.opacity(0.6)
            let icon = CGRect(x: center - 2.5, y: 87.5, width: 5, height: 5)
            context.fill(Path(roundedRect: icon, cornerRadius: 1.25), with: .color(color))
        }
    }
}

private extension GraphicsContext {
    func fillPill(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        fill(Capsule().path(in: rect), with: .color(color))
    }
}
