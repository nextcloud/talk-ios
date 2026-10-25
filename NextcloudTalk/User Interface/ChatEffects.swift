//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

// Small, purely decorative animations in the chat.
// All effects are skipped when "Reduce Motion" is enabled.
@MainActor
enum ChatEffects {

    // MARK: - Celebration

    // Emojis that let it rain confetti. Only emojis, so it works the same in every language.
    static let celebrationEmojis: Set<Character> = ["🎉", "🥳", "🎊", "🎂"]

    static func isCelebration(_ messageText: String?) -> Bool {
        guard let messageText else { return false }

        return messageText.contains { celebrationEmojis.contains($0) }
    }

    /// Lets confetti fall from the top of the view for a moment. The view is removed again afterwards.
    static func showConfetti(in view: UIView) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let confettiView = UIView(frame: view.bounds)
        confettiView.isUserInteractionEnabled = false
        confettiView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        confettiView.accessibilityElementsHidden = true
        view.addSubview(confettiView)

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: view.bounds.width, height: 1)
        emitter.beginTime = CACurrentMediaTime()

        let colors: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .systemPink]
        let confettiImage = self.confettiPieceImage()

        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = confettiImage
            cell.color = color.cgColor
            cell.birthRate = 10
            cell.lifetime = 6
            cell.velocity = 180
            cell.velocityRange = 60
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 6
            cell.yAcceleration = 120
            cell.spin = 3
            cell.spinRange = 4
            cell.scale = 0.6
            cell.scaleRange = 0.3
            cell.alphaSpeed = -0.12
            return cell
        }

        confettiView.layer.addSublayer(emitter)

        // Stop emitting new pieces after a short burst, then remove the view once all pieces are gone
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            emitter.birthRate = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            confettiView.removeFromSuperview()
        }
    }

    private static func confettiPieceImage() -> CGImage? {
        let size = CGSize(width: 8, height: 12)

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.cgImage
    }

    // MARK: - Animated emoji

    // How a message only consisting of a few emojis comes to life when it arrives
    enum EmojiAnimation: Equatable {
        case heartbeat, shake, bounce, wave, flicker, spin, pop
    }

    // Keyed by the first unicode scalar, so skin tones and other variations of an emoji are animated the same
    private static let emojiAnimations: [EmojiAnimation: String] = [
        .heartbeat: "❤🧡💛💚💙💜🖤🤍🤎🩷🩵🩶💖💗💓💞💕💘😍🥰😘",
        .shake: "😂🤣😆😹😡🤬😱😤",
        .bounce: "👍👏🙌💪🤝✅🙏🥳",
        .wave: "👋",
        .flicker: "🔥✨⚡🌟⭐💥",
        .spin: "🌀🌍🌎🌏⚽🏀😵"
    ]

    static func emojiAnimation(forEmojiMessage messageText: String) -> EmojiAnimation {
        guard let firstScalar = messageText.unicodeScalars.first else { return .pop }

        for (animation, emojis) in emojiAnimations where emojis.unicodeScalars.contains(firstScalar) {
            return animation
        }

        return .pop
    }

    static func animateEmoji(_ view: UIView, with animation: EmojiAnimation) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let keyframeAnimation: CAAnimation

        switch animation {
        case .heartbeat:
            keyframeAnimation = self.keyframes("transform.scale", values: [1, 1.3, 1, 1.3, 1], duration: 0.9)
        case .shake:
            keyframeAnimation = self.keyframes("transform.rotation.z", values: [0, -0.25, 0.25, -0.25, 0.25, 0], duration: 0.6)
        case .bounce:
            keyframeAnimation = self.keyframes("transform.translation.y", values: [0, -16, 0, -8, 0], duration: 0.7)
        case .wave:
            keyframeAnimation = self.keyframes("transform.rotation.z", values: [0, 0.4, -0.2, 0.4, -0.2, 0], duration: 1.0)
        case .flicker:
            let group = CAAnimationGroup()
            group.animations = [self.keyframes("opacity", values: [1, 0.4, 1, 0.6, 1], duration: 0.8),
                                self.keyframes("transform.scale", values: [1, 1.15, 0.95, 1.1, 1], duration: 0.8)]
            group.duration = 0.8
            keyframeAnimation = group
        case .spin:
            keyframeAnimation = self.keyframes("transform.rotation.z", values: [0, Double.pi, 2 * Double.pi], duration: 0.8)
        case .pop:
            keyframeAnimation = self.keyframes("transform.scale", values: [0.6, 1.25, 1], duration: 0.4)
        }

        view.layer.add(keyframeAnimation, forKey: "emojiAnimation")
    }

    private static func keyframes(_ keyPath: String, values: [Double], duration: CFTimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    // MARK: - Reaction burst

    /// Shows the emoji growing at the given point, while smaller copies of it fly outwards.
    static func showReactionBurst(_ emoji: String, at point: CGPoint, in view: UIView) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let mainLabel = self.emojiLabel(emoji, fontSize: 56)
        mainLabel.center = point
        mainLabel.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        view.addSubview(mainLabel)

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.8) {
            mainLabel.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.4, delay: 0.15, options: .curveEaseIn) {
                mainLabel.transform = CGAffineTransform(translationX: 0, y: -40).scaledBy(x: 0.6, y: 0.6)
                mainLabel.alpha = 0
            } completion: { _ in
                mainLabel.removeFromSuperview()
            }
        }

        let particleCount = 6

        for index in 0..<particleCount {
            let particleLabel = self.emojiLabel(emoji, fontSize: 20)
            particleLabel.center = point
            particleLabel.alpha = 0.9
            view.addSubview(particleLabel)

            let angle = (CGFloat(index) / CGFloat(particleCount)) * 2 * .pi + CGFloat.random(in: -0.3...0.3)
            let distance = CGFloat.random(in: 50...80)
            let translation = CGAffineTransform(translationX: cos(angle) * distance, y: sin(angle) * distance)

            UIView.animate(withDuration: 0.6, delay: 0.05, options: .curveEaseOut) {
                particleLabel.transform = translation.scaledBy(x: 0.5, y: 0.5)
                particleLabel.alpha = 0
            } completion: { _ in
                particleLabel.removeFromSuperview()
            }
        }
    }

    private static func emojiLabel(_ emoji: String, fontSize: CGFloat) -> UILabel {
        let label = UILabel()
        label.text = emoji
        label.font = .systemFont(ofSize: fontSize)
        label.isUserInteractionEnabled = false
        label.isAccessibilityElement = false
        label.sizeToFit()

        return label
    }
}
