import SwiftUI

struct EQGraphView: View {
    let bands: [EQBand]
    let gainBinding: (Int) -> Binding<Float>

    private let hPad: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            ZStack {
                EQGridBackground(hPad: hPad)
                EQCurveView(
                    bands: bands,
                    width: geo.size.width,
                    height: geo.size.height,
                    hPad: hPad
                )
                .allowsHitTesting(false)
                EQSlidersOverlay(
                    bands: bands,
                    hPad: hPad,
                    gainBinding: gainBinding
                )
            }
        }
        .frame(minHeight: 280)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

func eqXFor(freq: Float, width: CGFloat, hPad: CGFloat) -> CGFloat {
    let logMin = log10(CGFloat(20))
    let logMax = log10(CGFloat(20000))
    let t = (log10(CGFloat(freq)) - logMin) / (logMax - logMin)
    return hPad + t * (width - hPad * 2)
}

func eqYFor(gain: Float, height: CGFloat) -> CGFloat {
    height / 2 - CGFloat(gain) / 40 * height
}

struct EQGridBackground: View {
    let hPad: CGFloat
    private let gainLines: [Float] = [-18, -12, -6, 0, 6, 12, 18]
    private let freqLabels: [Float] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Canvas { ctx, size in
                let midY = size.height / 2

                for db in gainLines {
                    let y = midY - CGFloat(db) / 40 * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: hPad, y: y))
                    path.addLine(to: CGPoint(x: size.width - hPad, y: y))
                    let isCenter = db == 0
                    ctx.stroke(
                        path,
                        with: .color(.secondary.opacity(isCenter ? 0.35 : 0.15)),
                        lineWidth: isCenter ? 1.5 : 0.5
                    )
                }

                for freq in freqLabels {
                    let x = eqXFor(freq: freq, width: size.width, hPad: hPad)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
                }
            }

            ForEach(gainLines, id: \.self) { db in
                let y = h / 2 - CGFloat(db) / 40 * h
                Text(db == 0 ? "0 dB" : "\(Int(db))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .position(x: hPad / 2, y: y)
            }

            ForEach(freqLabels, id: \.self) { freq in
                let x = eqXFor(freq: freq, width: w, hPad: hPad)
                Text(freq >= 1000 ? "\(Int(freq / 1000))k" : "\(Int(freq))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .position(x: x, y: h - 8)
            }
        }
    }
}

struct EQCurveView: View {
    let bands: [EQBand]
    let width: CGFloat
    let height: CGFloat
    let hPad: CGFloat

    private var accentColor: Color {
        Color.accentColor
    }

    private var points: [CGPoint] {
        bands.map { band in
            CGPoint(
                x: eqXFor(freq: band.frequency, width: width, hPad: hPad),
                y: eqYFor(gain: band.gain, height: height)
            )
        }
    }

    var body: some View {
        ZStack {
            fillPath.fill(
                LinearGradient(
                    colors: [accentColor.opacity(0.25), accentColor.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            curvePath.stroke(accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    private var curvePath: Path {
        Path { path in
            guard !points.isEmpty else { return }
            path.move(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1], curr = points[i]
                let cp1 = CGPoint(x: (prev.x + curr.x) / 2, y: prev.y)
                let cp2 = CGPoint(x: (prev.x + curr.x) / 2, y: curr.y)
                path.addCurve(to: curr, control1: cp1, control2: cp2)
            }
        }
    }

    private var fillPath: Path {
        Path { path in
            guard !points.isEmpty else { return }
            let mid = height / 2
            path.move(to: CGPoint(x: points[0].x, y: mid))
            path.addLine(to: points[0])
            for i in 1..<points.count {
                let prev = points[i - 1], curr = points[i]
                let cp1 = CGPoint(x: (prev.x + curr.x) / 2, y: prev.y)
                let cp2 = CGPoint(x: (prev.x + curr.x) / 2, y: curr.y)
                path.addCurve(to: curr, control1: cp1, control2: cp2)
            }
            if let last = points.last {
                path.addLine(to: CGPoint(x: last.x, y: mid))
            }
            path.closeSubpath()
        }
    }
}

struct EQSlidersOverlay: View {
    let bands: [EQBand]
    let hPad: CGFloat
    let gainBinding: (Int) -> Binding<Float>

    var body: some View {
        GeometryReader { geo in
            ForEach(bands) { band in
                EQBandHandle(
                    band: band,
                    size: geo.size,
                    hPad: hPad,
                    gain: gainBinding(band.id)
                )
            }
        }
    }
}

struct EQBandHandle: View {
    let band: EQBand
    let size: CGSize
    let hPad: CGFloat
    @Binding var gain: Float
    @State private var isDragging = false
    @State private var dragStartGain: Float = 0

    private var handleX: CGFloat {
        eqXFor(freq: band.frequency, width: size.width, hPad: hPad)
    }

    private var handleY: CGFloat {
        eqYFor(gain: gain, height: size.height)
    }

    private var midY: CGFloat {
        size.height / 2
    }

    private var fillColor: Color {
        if gain == 0 { return Color.secondary.opacity(0.5) }
        return gain > 0 ? AppColors.eqPositiveGain : AppColors.eqNegativeGain
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 1)
                .frame(height: size.height)
                .position(x: handleX, y: midY)

            let barTop = min(handleY, midY)
            let barBottom = max(handleY, midY)
            Rectangle()
                .fill(fillColor.opacity(0.35))
                .frame(width: 3, height: max(1, barBottom - barTop))
                .position(x: handleX, y: (barTop + barBottom) / 2)

            Text(gain == 0 ? "0" : String(format: "%+.1f", gain))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(fillColor)
                .opacity(isDragging ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: isDragging)
                .position(x: handleX, y: gain >= 0 ? handleY - 16 : handleY + 16)

            Circle()
                .fill(fillColor)
                .frame(width: isDragging ? 16 : 11, height: isDragging ? 16 : 11)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: fillColor.opacity(0.6), radius: isDragging ? 8 : 3)
                .animation(.spring(response: 0.2), value: isDragging)
                .position(x: handleX, y: handleY)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartGain = gain
                            }
                            let delta = Float(-value.translation.height / size.height) * 40
                            gain = min(20, max(-20, dragStartGain + delta))
                        }
                        .onEnded { _ in isDragging = false }
                )
        }
        .frame(width: size.width, height: size.height)
    }
}
