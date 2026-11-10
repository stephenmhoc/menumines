import SwiftUI

struct ConfettiView: View {
    let isActive: Bool

    @State private var particles: [ConfettiParticle] = []
    @State private var animationStartTime: Date?
    @State private var showsReducedCelebration = false

    private let animationDuration: TimeInterval = 2.0
    private let particleCount = 50
    private let colors: [Color] = [.yellow, .orange, .red, .pink, .purple, .blue, .green]

    /// From the environment rather than asked once, so turning it on mid-celebration counts.
    @Environment(\.accessibilityReduceMotion) private var reduceMotionEnabled

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if reduceMotionEnabled {
                    reducedMotionCelebration
                } else if animationStartTime != nil {
                    TimelineView(.animation) { timeline in
                        let phase = calculatePhase(at: timeline.date)
                        ForEach(particles) { particle in
                            ConfettiParticleView(particle: particle, phase: phase)
                        }
                    }
                    .task(id: animationStartTime) {
                        guard animationStartTime != nil else { return }
                        try? await Task.sleep(for: .seconds(animationDuration))
                        animationStartTime = nil
                    }
                }
            }
            .onChange(of: isActive) { _, newValue in
                guard newValue else {
                    // A new board was dealt: nothing left to celebrate.
                    stopCelebration()
                    return
                }
                if reduceMotionEnabled {
                    showsReducedCelebration = true
                } else {
                    startCelebration(in: geometry.size)
                }
            }
            .onChange(of: reduceMotionEnabled) { _, reduce in
                if reduce {
                    stopCelebration()
                }
            }
            .task(id: showsReducedCelebration) {
                guard showsReducedCelebration else { return }
                try? await Task.sleep(for: .seconds(animationDuration))
                showsReducedCelebration = false
            }
        }
        .allowsHitTesting(false)
    }

    private var reducedMotionCelebration: some View {
        Text("🎉")
            .font(.system(size: 48))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(showsReducedCelebration ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: showsReducedCelebration)
    }

    private func calculatePhase(at date: Date) -> CGFloat {
        guard let startTime = animationStartTime else { return 0 }
        let elapsed = date.timeIntervalSince(startTime)
        return min(1, max(0, CGFloat(elapsed / animationDuration)))
    }

    private func initializeParticles(in size: CGSize) {
        particles = (0..<particleCount).map { _ in
            ConfettiParticle(
                color: colors.randomElement() ?? .yellow,
                startX: CGFloat.random(in: 0...size.width),
                startY: CGFloat.random(in: -50...(-10)),
                endY: size.height + 50,
                horizontalDrift: CGFloat.random(in: -30...30),
                rotation: CGFloat.random(in: 0...360),
                rotationSpeed: CGFloat.random(in: -360...360),
                delay: CGFloat.random(in: 0...0.5),
                size: CGFloat.random(in: 6...12)
            )
        }
    }

    private func startCelebration(in size: CGSize) {
        initializeParticles(in: size)
        animationStartTime = Date()
    }

    private func stopCelebration() {
        animationStartTime = nil
        particles = []
        showsReducedCelebration = false
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let horizontalDrift: CGFloat
    let rotation: CGFloat
    let rotationSpeed: CGFloat
    let delay: CGFloat
    let size: CGFloat
}

private struct ConfettiParticleView: View {
    let particle: ConfettiParticle
    let phase: CGFloat

    private var adjustedPhase: CGFloat {
        max(0, min(1, (phase - particle.delay) / (1 - particle.delay)))
    }

    /// Thrown up and falling back: quick at first, slowing as it drifts down, rather than
    /// sliding at one speed.
    private var fallProgress: CGFloat {
        let progress = adjustedPhase
        return 1 - (1 - progress) * (1 - progress) * (1 - progress)
    }

    private var currentY: CGFloat {
        particle.startY + (particle.endY - particle.startY) * fallProgress
    }

    private var currentX: CGFloat {
        particle.startX + particle.horizontalDrift * sin(adjustedPhase * .pi * 2)
    }

    private var currentRotation: CGFloat {
        particle.rotation + particle.rotationSpeed * fallProgress
    }

    private var opacity: CGFloat {
        switch adjustedPhase {
        case ..<0.1: adjustedPhase * 10
        case 0.8...: (1 - adjustedPhase) * 5
        default: 1
        }
    }

    var body: some View {
        Rectangle()
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size * 0.6)
            .rotationEffect(.degrees(currentRotation))
            .position(x: currentX, y: currentY)
            .opacity(opacity)
    }
}

#Preview("Confetti") {
    ConfettiPreviewContainer()
}

private struct ConfettiPreviewContainer: View {
    @State private var isActive = false

    var body: some View {
        ZStack {
            Color.gray.opacity(0.3)
            ConfettiView(isActive: isActive)
            VStack {
                Spacer()
                Button("Trigger Confetti") {
                    isActive = false
                    DispatchQueue.main.async {
                        isActive = true
                    }
                }
                .padding()
            }
        }
        .frame(width: 300, height: 400)
    }
}
