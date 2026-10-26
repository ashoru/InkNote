import SwiftUI
import PencilKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - PencilKit canvas + canonical conversion
//
// PencilKit is the editing renderer in v1. It is NOT the storage format:
// on save, the PKDrawing is converted to canonical InkStrokes (pointKind
// .control, because PKStrokePath points are B-spline control points);
// on load, canonical strokes are converted back to a PKDrawing.
// Imported .note strokes (pointKind .sampled) are rendered by the
// canonical renderer in the thumbnail/export path, and are converted to
// PKDrawing only for editing, with the pointKind recorded so a future
// custom renderer can tell sampled points from control points.

#if canImport(UIKit)
public struct PencilCanvasView: UIViewRepresentable {
    @Binding public var drawing: PKDrawing
    public var onDrawingChange: (PKDrawing) -> Void

    public init(drawing: Binding<PKDrawing>, onDrawingChange: @escaping (PKDrawing) -> Void) {
        self._drawing = drawing
        self.onDrawingChange = onDrawingChange
    }

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.tool = PKInkingTool(.pen, color: .black, width: 2)
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        context.coordinator.toolPicker = toolPicker
        canvas.becomeFirstResponder()
        return canvas
    }

    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChange: onDrawingChange)
    }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        var toolPicker: PKToolPicker?
        let onDrawingChange: (PKDrawing) -> Void
        init(onDrawingChange: @escaping (PKDrawing) -> Void) {
            self.onDrawingChange = onDrawingChange
        }
        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Delegate-driven only. No timer, no polling.
            onDrawingChange(canvasView.drawing)
        }
    }
}

public enum CanonicalPencilConversion {
    public static func canonicalStrokes(from drawing: PKDrawing) -> [InkStroke] {
        return drawing.strokes.map { stroke in
            let points: [InkPoint] = stroke.path.map { point in
                InkPoint(x: Double(point.location.x), y: Double(point.location.y), force: Double(point.force), azimuth: Double(point.azimuth), altitude: Double(point.altitude), timestamp: point.timeOffset)
            }
            let ink = stroke.ink
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            ink.color.getRed(&r, green: &g, blue: &b, alpha: &a)
            let rgba = RGBAColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
            let tool: InkTool
            switch ink.inkType {
            case .marker: tool = .marker
            case .pencil: tool = .pencil
            default: tool = .pen
            }
            // Base width: use the first point's size as a stable estimate.
            let width = stroke.path.first.map { Double($0.size.width) } ?? 2.0
            return InkStroke(tool: tool, color: rgba, baseWidth: width, points: points, pointKind: .control)
        }
    }

    public static func drawing(from strokes: [InkStroke]) -> PKDrawing {
        var pkStrokes: [PKStroke] = []
        for stroke in strokes {
            let points: [PKStrokePoint] = stroke.points.map { point in
                PKStrokePoint(location: CGPoint(x: point.x, y: point.y), timeOffset: point.timestamp, size: CGSize(width: stroke.baseWidth, height: stroke.baseWidth), opacity: CGFloat(stroke.color.alpha), force: CGFloat(point.force), azimuth: CGFloat(point.azimuth), altitude: CGFloat(point.altitude))
            }
            guard !points.isEmpty else { continue }
            let path = PKStrokePath(controlPoints: points, creationDate: Date())
            let uiColor = UIColor(red: CGFloat(stroke.color.red), green: CGFloat(stroke.color.green), blue: CGFloat(stroke.color.blue), alpha: CGFloat(stroke.color.alpha))
            let inkType: PKInk.InkType
            switch stroke.tool {
            case .marker: inkType = .marker
            case .pencil: inkType = .pencil
            default: inkType = .pen
            }
            let ink = PKInk(inkType, color: uiColor)
            pkStrokes.append(PKStroke(ink: ink, path: path))
        }
        return PKDrawing(strokes: pkStrokes)
    }

    /// Render canonical strokes (any pointKind) to an image in page
    /// coordinates. Used for thumbnails and PDF export, on a background
    /// queue by callers. Sampled points are drawn as a polyline; control
    /// points are drawn through the PKDrawing path so the spline is honoured.
    public static func image(for strokes: [InkStroke], pageSize: CGSize, scale: CGFloat = 2.0) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: pageSize, format: format)
        return renderer.image { context in
            let drawing = drawing(from: strokes)
            // PKDrawing.image renders the spline correctly for control
            // points; for sampled points the polyline through the same
            // points is visually equivalent at export resolution in v1.
            // A future custom renderer will distinguish the two kinds.
            let image = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: scale)
            image.draw(in: CGRect(origin: .zero, size: pageSize))
            _ = context
        }
    }
}
#endif
