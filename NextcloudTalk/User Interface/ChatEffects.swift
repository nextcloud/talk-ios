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
