import SwiftUI

// MARK: - Self-drawn paper templates (no copied template images)
//
// Templates are drawn with SwiftUI Path only: lines, grid and dots.
// No other app template image, PDF or asset is used, copied or traced.
// The spacing is in page points; the view is scaled by its parent to
// the on-screen page size, so the template never depends on device scale.

public struct PaperTemplateView: View {
    public var template: PaperTemplate
    public var pageSize: CGSize

    public init(template: PaperTemplate, pageSize: CGSize) {
        self.template = template
        self.pageSize = pageSize
    }

    public var body: some View {
        ZStack {
            Color.white
            Canvas { context, size in
                guard template != .blank else { return }
                let spacing: CGFloat = 32
                var path = Path()
                switch template {
                case .lines:
                    var y: CGFloat = spacing
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += spacing
                    }
                case .grid:
                    var x: CGFloat = 0
                    while x <= size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += spacing
                    }
                    var y: CGFloat = 0
                    while y <= size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += spacing
                    }
                case .dotted:
                    var y: CGFloat = spacing
                    while y < size.height {
                        var x: CGFloat = spacing
                        while x < size.width {
                            path.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                            x += spacing
                        }
                        y += spacing
                    }
                case .blank:
                    break
                }
                context.stroke(path, with: .color(Color.gray.opacity(0.35)), lineWidth: 0.5)
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
    }
}
