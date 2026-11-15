//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

enum NCActivityIndicatorMode {
    case indeterminate
    /// Draws an arc for `progress`, growing clockwise from twelve o'clock
    case determinate
}

/// A circular progress indicator with an animated switch between spinning and showing a progress
class NCActivityIndicator: UIView {

    // MARK: - Animation constants

    private static let cycleDuration: CFTimeInterval = 1.7

    /// Must stay a whole number, the cycle repeats by replaying its values and has to end on its starting angle
    private static let turnsPerCycle: CGFloat = 2

    private static let progressDuration: CFTimeInterval = 0.3
    private static let handoverFillDuration: CFTimeInterval = 0.4

    /// Part of a cycle a hand-over brakes over, the same every time so each one comes to rest the same way
    private static let brakeSpan: CGFloat = 0.5

    /// Also the starting slope of the braking curve, at most 3 or the curve turns backwards before it stops
    private static let handoverStretch: CGFloat = 1.5

    private static let resumeDuration: CFTimeInterval = 0.4
    private static let entryDuration: CFTimeInterval = cycleDuration / 2

    /// Arc lengths as a fraction of a full turn
    private static let minimumArc: CGFloat = 0.08
    private static let maximumArc: CGFloat = 0.78
    private static let arcSweep = maximumArc - minimumArc

    /// Speed of the tail where the cycle starts, in turns per second
    private static let cycleStartSpeed = (turnsPerCycle - arcSweep) / CGFloat(cycleDuration)

    private static let samplesPerSecond: Double = 72

    private static let strokeAnimationKey = "stroke"
    private static let rotationAnimationKey = "rotation"
    private static let fillAnimationKey = "fill"
    private static let entryStrokeAnimationKey = "entryStroke"
    private static let entryRotationAnimationKey = "entryRotation"

    private static let fullTurn = 2 * CGFloat.pi

    // MARK: - Appearance

    var color: UIColor = .secondaryLabel {
        didSet { self.applyColor() }
    }

    var strokeWidth: CGFloat = 2.5 {
        didSet {
            self.shapeLayer.lineWidth = self.strokeWidth
            self.sizeChanged()
        }
    }

    /// To the outer edge of the stroke, so the ring fits a view of twice the radius
    var radius: CGFloat = 12.0 {
        didSet {
            // Set on every layout pass by some callers
            guard oldValue != self.radius else { return }

            self.sizeChanged()
        }
    }

    // MARK: - State

    private(set) var isAnimating: Bool = false

    var indicatorMode: NCActivityIndicatorMode = .indeterminate {
        didSet {
            guard oldValue != self.indicatorMode else { return }

            // Only animated when there is something on screen to hand over from
            self.applyCurrentMode(animated: self.isAnimating && self.window != nil)
        }
    }

    /// From 0 to 1, only drawn in `determinate` mode
    private var currentProgress: Float = 0

    /// Never shorter than the stub the spin ends on, so a hand-over does not shrink back before it grows
    private var displayedProgress: CGFloat {
        max(CGFloat(self.currentProgress), NCActivityIndicator.minimumArc)
    }

    /// The cycle is worked out from the clock, the presentation layer is unreliable in the turn its animations change
    private var cycleStartTime: CFTimeInterval = 0
    private var cycleStartPhase: CGFloat = 0
    private var cycleBaseRotation: CGFloat = 0

    private var handover: Handover?
    private var fill: ArcMotion?

    private let shapeLayer = CAShapeLayer()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }

    private func commonInit() {
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false
        self.isHidden = true

        self.shapeLayer.fillColor = nil
        self.shapeLayer.lineCap = .round
        self.shapeLayer.lineWidth = self.strokeWidth
        self.shapeLayer.strokeStart = 0
        self.shapeLayer.strokeEnd = NCActivityIndicator.minimumArc
        self.layer.addSublayer(self.shapeLayer)

        self.applyColor()
        self.sizeChanged()

        NotificationCenter.default.addObserver(self, selector: #selector(restartIfNeeded),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settleIfNeeded),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: self.radius * 2 + self.strokeWidth, height: self.radius * 2 + self.strokeWidth)
    }

    private func sizeChanged() {
        self.invalidateIntrinsicContentSize()
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Not `frame`, which would fight with the rotation transform the layer carries
        self.shapeLayer.bounds = CGRect(origin: .zero, size: self.bounds.size)
        self.shapeLayer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)

        let center = CGPoint(x: self.bounds.width / 2, y: self.bounds.height / 2)
        self.shapeLayer.path = UIBezierPath(arcCenter: center, radius: max(self.radius - self.strokeWidth / 2, 0), startAngle: -.pi / 2,
                                            endAngle: 1.5 * .pi, clockwise: true).cgPath

        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            self.applyColor()
        }
    }

    private func applyColor() {
        self.shapeLayer.strokeColor = self.color.resolvedColor(with: self.traitCollection).cgColor
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if self.window == nil {
            self.settleIfNeeded()
        } else {
            self.restartIfNeeded()
        }
    }

    /// Animations are dropped when the app is suspended or the view leaves its window
    @objc private func restartIfNeeded() {
        guard self.isAnimating, self.window != nil else { return }

        switch self.indicatorMode {
        case .indeterminate:
            // Only when they really went away, a view that is animated in moves to a window twice
            if self.shapeLayer.animation(forKey: NCActivityIndicator.rotationAnimationKey) == nil {
                self.startIndeterminate(animated: false)
            }
        case .determinate:
            if self.shapeLayer.animationKeys()?.isEmpty ?? true {
                self.settleIfNeeded()
            }
        }
    }

    /// A hand-over or fill cut short would replay from stale times, so a determinate ring goes to rest before they are dropped
    @objc private func settleIfNeeded() {
        guard self.isAnimating, self.indicatorMode == .determinate else { return }

        self.clearMotions()
        self.setLayerState(arc: self.displayedProgress, rotation: 0)
    }

    // MARK: - Animation control

    func startAnimating() {
        self.isHidden = false

        // Not restarting a running indicator, callers show the same one repeatedly
        guard !self.isAnimating else { return }

        self.isAnimating = true
        self.applyCurrentMode(animated: false)
    }

    func stopAnimating() {
        guard self.isAnimating else { return }

        self.isAnimating = false
        self.isHidden = true
        self.clearMotions()
    }

    func setProgress(_ progress: Float, animated: Bool) {
        self.currentProgress = min(max(progress, 0), 1)

        guard self.indicatorMode == .determinate else { return }

        // Callers set the mode and the progress one after the other, the cycle is left to play out
        if self.isAwaitingHandover {
            self.addHandoverFill()
            return
        }

        let target = self.displayedProgress

        guard animated, self.isAnimating, self.window != nil else {
            self.clearMotions()
            self.setLayerState(arc: target, rotation: self.modelRotation)
            return
        }

        let now = CACurrentMediaTime()
        let current = self.determinateState(at: now)

        // Carrying the speed over keeps a stream of updates from restarting its easing on every one
        let velocity = self.fill?.velocity(at: now) ?? 0
        self.startFill(ArcMotion(start: now, duration: NCActivityIndicator.progressDuration,
                                 from: current.arc, velocity: velocity, to: target))
    }

    private func startFill(_ fill: ArcMotion) {
        self.fill = fill

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.shapeLayer.strokeEnd = fill.to
        CATransaction.commit()

        self.addKeyframes(keyPath: "strokeEnd", key: NCActivityIndicator.fillAnimationKey,
                          from: fill.start, to: fill.end) { fill.value(at: $0) }
    }

    private func applyCurrentMode(animated: Bool) {
        guard self.isAnimating else {
            self.clearMotions()
            self.setLayerState(arc: self.indicatorMode == .determinate ? self.displayedProgress : NCActivityIndicator.minimumArc, rotation: 0)
            return
        }

        switch self.indicatorMode {
        case .determinate:
            if animated {
                self.scheduleHandover()
            } else {
                self.clearMotions()
                self.setLayerState(arc: self.displayedProgress, rotation: 0)
            }
        case .indeterminate:
            self.startIndeterminate(animated: animated)
        }
    }

    private func clearMotions() {
        self.handover = nil
        self.fill = nil
        self.shapeLayer.removeAllAnimations()
    }

    // MARK: - Indeterminate to determinate

    /// The cycle ends on the stub at twelve o'clock, where a determinate arc starts, and is braked to rest there
    private func scheduleHandover() {
        // While an entry is still getting up to speed, the hand-over follows on from it
        let start = max(CACurrentMediaTime(), self.cycleStartTime)
        let phase = self.cyclePhase(at: start)
        var endPhase = floor(phase) + 1

        // Not enough of this cycle left to brake in
        if endPhase - phase < NCActivityIndicator.brakeSpan {
            endPhase += 1
        }

        let brakePhase = endPhase - NCActivityIndicator.brakeSpan
        let handover = Handover(start: start, brakeStart: start + CFTimeInterval(brakePhase - phase) * NCActivityIndicator.cycleDuration,
                                brakePhase: brakePhase)
        self.handover = handover
        self.fill = nil

        // The entry animations, if any, are left to finish
        self.shapeLayer.removeAnimation(forKey: NCActivityIndicator.strokeAnimationKey)
        self.shapeLayer.removeAnimation(forKey: NCActivityIndicator.rotationAnimationKey)
        self.shapeLayer.removeAnimation(forKey: NCActivityIndicator.fillAnimationKey)

        self.setLayerState(arc: self.displayedProgress, rotation: self.cycleRotation(atPhase: endPhase))

        // Both this and the fill run off Core Animation's clock, a main thread callback is never punctual enough
        self.addKeyframes(keyPath: "strokeEnd", key: NCActivityIndicator.strokeAnimationKey,
                          from: handover.start, to: handover.end) { NCActivityIndicator.arcLength(atPhase: handover.position(at: $0)) }
        self.addKeyframes(keyPath: "transform.rotation.z", key: NCActivityIndicator.rotationAnimationKey,
                          from: handover.start, to: handover.end) { self.cycleRotation(atPhase: handover.position(at: $0)) }

        self.addHandoverFill()
    }

    /// Separate so a progress that arrives while still braking only has to retarget the fill
    private func addHandoverFill() {
        guard let handover = self.handover else { return }

        self.startFill(ArcMotion(start: handover.end, duration: NCActivityIndicator.handoverFillDuration,
                                 from: NCActivityIndicator.minimumArc, velocity: 0, to: self.displayedProgress))
    }

    private var isAwaitingHandover: Bool {
        guard let handover = self.handover else { return false }

        return CACurrentMediaTime() < handover.end
    }

    // MARK: - Determinate to indeterminate

    private func startIndeterminate(animated: Bool) {
        let now = CACurrentMediaTime()

        guard animated else {
            self.clearMotions()
            self.cycleStartPhase = 0
            self.cycleBaseRotation = 0
            self.cycleStartTime = now
            self.setLayerState(arc: NCActivityIndicator.minimumArc, rotation: 0)
            self.addCycleAnimations()
            return
        }

        if let handover = self.handover, now < handover.end {
            self.resumeCycle(from: handover, at: now)
        } else {
            self.enterCycle(at: now)
        }
    }

    /// Back to spinning before a hand-over came to rest, picking the cycle up at the speed it had braked to
    private func resumeCycle(from handover: Handover, at now: CFTimeInterval) {
        self.handover = nil
        self.fill = nil
        self.shapeLayer.removeAnimation(forKey: NCActivityIndicator.fillAnimationKey)

        // Still in the entry, the cycle just goes on after it
        guard now >= handover.start else {
            self.setLayerState(arc: NCActivityIndicator.arcLength(atPhase: self.cycleStartPhase), rotation: self.cycleBaseRotation)
            self.addCycleAnimations()
            return
        }

        let position = handover.position(at: now)
        let rotation = self.cycleRotation(atPhase: position)
        let duration = NCActivityIndicator.resumeDuration

        // Travelling at the average of the two speeds keeps the curve between them from overshooting
        let startSlope = handover.speed(at: now) * CGFloat(duration)
        let endSlope = CGFloat(duration / NCActivityIndicator.cycleDuration)
        let travel = (startSlope + endSlope) / 2

        let phase: (CFTimeInterval) -> CGFloat = { time in
            let fraction = min(max(CGFloat((time - now) / duration), 0), 1)
            return position + NCActivityIndicator.hermite(fraction, from: 0, slope: startSlope, to: travel, endSlope: endSlope)
        }
        let turn: (CGFloat) -> CGFloat = { phase in
            rotation + (NCActivityIndicator.rotationTurns(atPhase: phase) - NCActivityIndicator.rotationTurns(atPhase: position)) * NCActivityIndicator.fullTurn
        }

        self.shapeLayer.removeAllAnimations()
        self.cycleStartPhase = position + travel
        self.cycleBaseRotation = turn(position + travel)
        self.cycleStartTime = now + duration
        self.setLayerState(arc: NCActivityIndicator.arcLength(atPhase: self.cycleStartPhase), rotation: self.cycleBaseRotation)

        self.addKeyframes(keyPath: "strokeEnd", key: NCActivityIndicator.entryStrokeAnimationKey, from: now, to: now + duration) {
            NCActivityIndicator.arcLength(atPhase: phase($0))
        }
        self.addKeyframes(keyPath: "transform.rotation.z", key: NCActivityIndicator.entryRotationAnimationKey, from: now, to: now + duration) {
            turn(phase($0))
        }

        self.addCycleAnimations()
    }

    /// The arc shrinks to the stub while the tail goes on to twelve o'clock, where a later hand-over needs the cycle to end
    private func enterCycle(at now: CFTimeInterval) {
        let current = self.determinateState(at: now)
        var duration = NCActivityIndicator.entryDuration

        self.clearMotions()

        // The tail has to go at least `shrink + finalSpeed / 3` for the head to start from standstill and never turn back
        var finalSpeed = NCActivityIndicator.cycleStartSpeed * CGFloat(duration)
        let shrink = max(current.arc - NCActivityIndicator.minimumArc, 0)
        let startTurns = current.rotation / NCActivityIndicator.fullTurn
        let travel = (startTurns + shrink + finalSpeed / 3 - 1e-6).rounded(.up) - startTurns

        // A nearly closed ring has to go round twice, which gets more time so it does not race
        if travel > 1.5 {
            duration *= 1.5
            finalSpeed = NCActivityIndicator.cycleStartSpeed * CGFloat(duration)
        }

        self.cycleStartPhase = 0
        self.cycleBaseRotation = current.rotation + travel * NCActivityIndicator.fullTurn
        self.cycleStartTime = now + duration

        self.setLayerState(arc: NCActivityIndicator.minimumArc, rotation: self.cycleBaseRotation)

        self.addKeyframes(keyPath: "strokeEnd", key: NCActivityIndicator.entryStrokeAnimationKey, from: now, to: now + duration) {
            let fraction = NCActivityIndicator.smoothStep(CGFloat(($0 - now) / duration))
            return current.arc + (NCActivityIndicator.minimumArc - current.arc) * fraction
        }
        self.addKeyframes(keyPath: "transform.rotation.z", key: NCActivityIndicator.entryRotationAnimationKey, from: now, to: now + duration) {
            let fraction = min(max(CGFloat(($0 - now) / duration), 0), 1)
            return current.rotation + NCActivityIndicator.fullTurn * NCActivityIndicator.hermite(fraction, from: 0, slope: 0, to: travel, endSlope: finalSpeed)
        }

        self.addCycleAnimations()
    }

    // MARK: - Cycle

    private func addCycleAnimations() {
        let start = self.cycleStartTime
        let end = start + NCActivityIndicator.cycleDuration

        self.addKeyframes(keyPath: "strokeEnd", key: NCActivityIndicator.strokeAnimationKey, from: start, to: end, repeating: true) {
            NCActivityIndicator.arcLength(atPhase: self.cyclePhase(at: $0))
        }
        self.addKeyframes(keyPath: "transform.rotation.z", key: NCActivityIndicator.rotationAnimationKey, from: start, to: end, repeating: true) {
            self.cycleRotation(atPhase: self.cyclePhase(at: $0))
        }
    }

    private func cyclePhase(at time: CFTimeInterval) -> CGFloat {
        self.cycleStartPhase + CGFloat((time - self.cycleStartTime) / NCActivityIndicator.cycleDuration)
    }

    /// Angle of the tail, unwrapped, so it keeps growing across cycles
    private func cycleRotation(atPhase phase: CGFloat) -> CGFloat {
        let travelled = NCActivityIndicator.rotationTurns(atPhase: phase) - NCActivityIndicator.rotationTurns(atPhase: self.cycleStartPhase)

        return self.cycleBaseRotation + travelled * NCActivityIndicator.fullTurn
    }

    // MARK: - Layer helpers

    private func addKeyframes(keyPath: String, key: String, from start: CFTimeInterval, to end: CFTimeInterval,
                              repeating: Bool = false, value: (CFTimeInterval) -> CGFloat) {
        let duration = end - start
        let steps = max(Int((duration * NCActivityIndicator.samplesPerSecond).rounded(.up)), 2)

        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0...steps).map { value(start + duration * CFTimeInterval($0) / CFTimeInterval(steps)) }
        // Linear interpolation would step the speed at every sample and show as a stutter
        animation.calculationMode = .cubic
        // Always explicit, left at 0 it is only filled in at commit, after the clock the curves were worked out from
        animation.beginTime = self.shapeLayer.convertTime(start, from: nil)
        animation.duration = duration
        animation.repeatCount = repeating ? .infinity : 1

        self.shapeLayer.add(animation, forKey: key)
    }

    private func setLayerState(arc: CGFloat, rotation: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.shapeLayer.strokeEnd = arc
        self.shapeLayer.setValue(rotation, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
    }

    private var modelRotation: CGFloat {
        CGFloat((self.shapeLayer.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? 0)
    }

    private func determinateState(at time: CFTimeInterval) -> (arc: CGFloat, rotation: CGFloat) {
        if let fill = self.fill, time < fill.end {
            return (fill.value(at: time), self.modelRotation)
        }

        return (self.shapeLayer.strokeEnd, self.modelRotation)
    }

    // MARK: - Motions

    /// An arc length moving to a target, starting at the speed it already had and ending at rest
    private struct ArcMotion {
        let start: CFTimeInterval
        let duration: CFTimeInterval
        let from: CGFloat
        let to: CGFloat
        let slope: CGFloat

        var end: CFTimeInterval { self.start + self.duration }

        init(start: CFTimeInterval, duration: CFTimeInterval, from: CGFloat, velocity: CGFloat, to: CGFloat) {
            self.start = start
            self.duration = duration
            self.from = from
            self.to = to

            // Only kept while it heads the same way, and capped so the curve does not overshoot the target
            let distance = to - from
            let slope = velocity * CGFloat(duration)
            self.slope = slope * distance <= 0 ? 0 : (abs(slope) > abs(3 * distance) ? 3 * distance : slope)
        }

        private func fraction(at time: CFTimeInterval) -> CGFloat {
            min(max(CGFloat((time - self.start) / self.duration), 0), 1)
        }

        func value(at time: CFTimeInterval) -> CGFloat {
            NCActivityIndicator.hermite(self.fraction(at: time), from: self.from, slope: self.slope, to: self.to, endSlope: 0)
        }

        func velocity(at time: CFTimeInterval) -> CGFloat {
            guard time >= self.start, time < self.end else { return 0 }

            return NCActivityIndicator.hermiteDerivative(self.fraction(at: time), from: self.from, slope: self.slope, to: self.to, endSlope: 0) / CGFloat(self.duration)
        }
    }

    /// The rest of a cycle, at full speed up to `brakePhase` and braked to rest from there
    private struct Handover {
        let start: CFTimeInterval
        let brakeStart: CFTimeInterval
        let brakePhase: CGFloat

        private static let brakeDuration = CFTimeInterval(NCActivityIndicator.brakeSpan * NCActivityIndicator.handoverStretch) * NCActivityIndicator.cycleDuration

        var end: CFTimeInterval { self.brakeStart + Handover.brakeDuration }

        private func brakeFraction(at time: CFTimeInterval) -> CGFloat {
            min(CGFloat((time - self.brakeStart) / Handover.brakeDuration), 1)
        }

        func position(at time: CFTimeInterval) -> CGFloat {
            guard time > self.brakeStart else {
                return self.brakePhase - CGFloat((self.brakeStart - time) / NCActivityIndicator.cycleDuration)
            }

            let braked = NCActivityIndicator.hermite(self.brakeFraction(at: time), from: 0, slope: NCActivityIndicator.handoverStretch, to: 1, endSlope: 0)

            return self.brakePhase + NCActivityIndicator.brakeSpan * braked
        }

        /// In cycles per second
        func speed(at time: CFTimeInterval) -> CGFloat {
            guard time > self.brakeStart else { return 1 / CGFloat(NCActivityIndicator.cycleDuration) }

            let slope = NCActivityIndicator.hermiteDerivative(self.brakeFraction(at: time), from: 0, slope: NCActivityIndicator.handoverStretch, to: 1, endSlope: 0)

            return NCActivityIndicator.brakeSpan * slope / CGFloat(Handover.brakeDuration)
        }
    }

    // MARK: - Curves

    /// Length of the arc in turns, growing over the first half of the cycle and shrinking over the second
    private static func arcLength(atPhase phase: CGFloat) -> CGFloat {
        let phase = phase - floor(phase)

        if phase < 0.5 {
            return minimumArc + arcSweep * smoothStep(phase * 2)
        }

        return maximumArc - arcSweep * smoothStep((phase - 0.5) * 2)
    }

    /// How far the tail has travelled in turns, exactly `turnsPerCycle` per cycle so it repeats without a seam
    private static func rotationTurns(atPhase phase: CGFloat) -> CGFloat {
        let cycles = floor(phase)
        let phase = phase - cycles
        let catchUp = phase < 0.5 ? 0 : arcSweep * smoothStep((phase - 0.5) * 2)

        return cycles * turnsPerCycle + (turnsPerCycle - arcSweep) * phase + catchUp
    }

    private static func smoothStep(_ value: CGFloat) -> CGFloat {
        let value = min(max(value, 0), 1)

        return value * value * (3 - 2 * value)
    }

    /// Cubic Hermite curve over 0...1 between two values, with the slopes it leaves and arrives at
    private static func hermite(_ t: CGFloat, from: CGFloat, slope: CGFloat, to: CGFloat, endSlope: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t

        return (2 * t3 - 3 * t2 + 1) * from + (t3 - 2 * t2 + t) * slope + (3 * t2 - 2 * t3) * to + (t3 - t2) * endSlope
    }

    private static func hermiteDerivative(_ t: CGFloat, from: CGFloat, slope: CGFloat, to: CGFloat, endSlope: CGFloat) -> CGFloat {
        let t2 = t * t

        return (6 * t2 - 6 * t) * from + (3 * t2 - 4 * t + 1) * slope + (6 * t - 6 * t2) * to + (3 * t2 - 2 * t) * endSlope
    }
}
