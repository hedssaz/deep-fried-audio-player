//
//  WaveformView.swift
//  Deep-Fried Audio Player
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

struct WaveformView: View {
    let originalBuffer: AudioBuffer?
    let processedBuffer: AudioBuffer?
    let isProcessedStale: Bool

    var body: some View {
        if originalBuffer == nil, processedBuffer == nil {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let originalBuffer {
                    WaveformPanel(
                        titleKey: "waveform.original",
                        buffer: originalBuffer,
                        tint: .accentColor
                    )
                }

                if let processedBuffer {
                    WaveformPanel(
                        titleKey: "waveform.processed",
                        buffer: processedBuffer,
                        tint: .orange
                    )

                    if isProcessedStale {
                        Label("waveform.processedStale", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("waveformStaleIndicator")
                    }
                }
            }
            .accessibilityIdentifier("waveformView")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("waveform.empty")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .accessibilityIdentifier("waveformPlaceholder")
    }
}

private struct WaveformPanel: View {
    let titleKey: LocalizedStringKey
    let buffer: AudioBuffer
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                let targetCount = max(48, min(700, Int(proxy.size.width)))
                let samples = WaveformDownsampler.downsample(
                    buffer,
                    targetSampleCount: targetCount
                )

                WaveformPlot(samples: samples, tint: tint)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: 112)
        }
    }
}

private struct WaveformPlot: View {
    let samples: [WaveformSample]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty, size.width > 0, size.height > 0 else {
                return
            }

            let centerY = size.height / 2.0
            let usableHeight = size.height * 0.82
            let xStep = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : 0
            var centerLine = Path()
            var waveform = Path()

            centerLine.move(to: CGPoint(x: 0, y: centerY))
            centerLine.addLine(to: CGPoint(x: size.width, y: centerY))

            for sample in samples {
                let x = CGFloat(sample.index) * xStep
                let top = centerY - CGFloat(sample.maximum) * usableHeight / 2.0
                let bottom = centerY - CGFloat(sample.minimum) * usableHeight / 2.0
                waveform.move(to: CGPoint(x: x, y: top))
                waveform.addLine(to: CGPoint(x: x, y: bottom))
            }

            context.stroke(centerLine, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            context.stroke(
                waveform,
                with: .color(tint),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
        }
    }
}
