// MIT License
//
// Copyright (c) 2021 Daniel Gauthier
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// From https://github.com/danielmgauthier/ViewControllerTransitionExample
// SPDX-License-Identifier: MIT

import UIKit

class StandardInteractionController: NSObject, InteractionControlling {
    var interactionInProgress = false
    private weak var viewController: CustomPresentable!
    private weak var transitionContext: UIViewControllerContextTransitioning?

    private var interactionDistance: CGFloat = 0
    private var interruptedTranslation: CGFloat = 0
    private var presentedFrame: CGRect?
    private var cancellationAnimator: UIViewPropertyAnimator?

    // MARK: - Setup
    init(viewController: CustomPresentable) {
        self.viewController = viewController
        super.init()

        prepareGestureRecognizer(in: viewController.view)

        if let scrollView = viewController.dismissalHandlingScrollView {
            resolveScrollViewGestures(scrollView)
        }

        // Round corners only at the top for the presented viewController
        self.viewController.view.clipsToBounds = true
        self.viewController.view.layer.cornerRadius = 10
        self.viewController.view.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
    }

    private func prepareGestureRecognizer(in view: UIView) {
        let gesture = OneWayPanGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        gesture.delegate = self

        view.addGestureRecognizer(gesture)
    }

    private func resolveScrollViewGestures(_ scrollView: UIScrollView) {
        let scrollGestureRecognizer = OneWayPanGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        scrollGestureRecognizer.delegate = self

        scrollView.addGestureRecognizer(scrollGestureRecognizer)
        scrollView.panGestureRecognizer.require(toFail: scrollGestureRecognizer)
    }

    // MARK: - Gesture handling
    @objc func handleGesture(_ gestureRecognizer: OneWayPanGestureRecognizer) {
        guard let superview = gestureRecognizer.view?.superview else { return }
        let translation = gestureRecognizer.translation(in: superview).y
        let velocity = gestureRecognizer.velocity(in: superview).y

        switch gestureRecognizer.state {
        case .began: gestureBegan()
        case .changed: gestureChanged(translation: translation + interruptedTranslation, velocity: velocity)
        case .cancelled: gestureCancelled(translation: translation + interruptedTranslation, velocity: velocity)
        case .ended: gestureEnded(translation: translation + interruptedTranslation, velocity: velocity)
        default: break
        }
    }

    private func gestureBegan() {
        disableOtherTouches()
        cancellationAnimator?.stopAnimation(true)

        if let presentedFrame = presentedFrame {
            interruptedTranslation = viewController.view.frame.minY - presentedFrame.minY
        }

        if !interactionInProgress {
            interactionInProgress = true
            viewController.dismiss(animated: true)
        }
    }

    private func gestureChanged(translation: CGFloat, velocity: CGFloat) {
        var progress = interactionDistance == 0 ? 0 : (translation / interactionDistance)
        if progress < 0 { progress /= (1.0 + abs(progress * 20)) }
        update(progress: progress)
    }

    private func gestureCancelled(translation: CGFloat, velocity: CGFloat) {
        cancel(initialSpringVelocity: springVelocity(distanceToTravel: -translation, gestureVelocity: velocity))
    }

    private func gestureEnded(translation: CGFloat, velocity: CGFloat) {
        if velocity > 300 || (translation > interactionDistance / 2.0 && velocity > -300) {
            finish(initialSpringVelocity: springVelocity(distanceToTravel: interactionDistance - translation, gestureVelocity: velocity))
        } else {
            cancel(initialSpringVelocity: springVelocity(distanceToTravel: -translation, gestureVelocity: velocity))
        }
    }

    // MARK: - Transition controlling
    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        let presentedViewController = transitionContext.viewController(forKey: .from)!
        presentedFrame = transitionContext.finalFrame(for: presentedViewController)
        self.transitionContext = transitionContext
        interactionDistance = transitionContext.containerView.bounds.height - presentedFrame!.minY
    }

    func update(progress: CGFloat) {
        guard let transitionContext = transitionContext, let presentedFrame = presentedFrame else { return }
        transitionContext.updateInteractiveTransition(progress)
        let presentedViewController = transitionContext.viewController(forKey: .from)!
        presentedViewController.view.frame = CGRect(x: presentedFrame.minX, y: presentedFrame.minY + interactionDistance * progress, width: presentedFrame.width, height: presentedFrame.height)

        if let modalPresentationController = presentedViewController.presentationController as? ModalPresentationController {
            modalPresentationController.fadeView.alpha = 1.0 - progress

        }
    }

    func cancel(initialSpringVelocity: CGFloat) {
        guard let transitionContext = transitionContext, let presentedFrame = presentedFrame else { return }
        let presentedViewController = transitionContext.viewController(forKey: .from)!

        let timingParameters = UISpringTimingParameters(dampingRatio: 0.8, initialVelocity: CGVector(dx: 0, dy: initialSpringVelocity))
        cancellationAnimator = UIViewPropertyAnimator(duration: 0.5, timingParameters: timingParameters)

        cancellationAnimator?.addAnimations {
            presentedViewController.view.frame = presentedFrame
            if let modalPresentationController = presentedViewController.presentationController as? ModalPresentationController {
                modalPresentationController.fadeView.alpha = 1.0
            }
        }

        cancellationAnimator?.addCompletion { _ in
            transitionContext.cancelInteractiveTransition()
            transitionContext.completeTransition(false)
            self.interactionInProgress = false
            self.enableOtherTouches()
        }

        cancellationAnimator?.startAnimation()
    }

    func finish(initialSpringVelocity: CGFloat) {
        guard let transitionContext = transitionContext,
              let presentedFrame = presentedFrame,
              let presentedViewController = transitionContext.viewController(forKey: .from) as? CustomPresentable
        else { return }

        let dismissedFrame = CGRect(x: presentedFrame.minX, y: transitionContext.containerView.bounds.height, width: presentedFrame.width, height: presentedFrame.height)

        let timingParameters = UISpringTimingParameters(dampingRatio: 0.8, initialVelocity: CGVector(dx: 0, dy: initialSpringVelocity))
        let finishAnimator = UIViewPropertyAnimator(duration: 0.5, timingParameters: timingParameters)

        finishAnimator.addAnimations {
            presentedViewController.view.frame = dismissedFrame
            if let modalPresentationController = presentedViewController.presentationController as? ModalPresentationController {
                modalPresentationController.fadeView.alpha = 0.0
            }
        }

        finishAnimator.addCompletion { _ in
            transitionContext.finishInteractiveTransition()
            transitionContext.completeTransition(true)
            self.interactionInProgress = false
        }

        finishAnimator.startAnimation()
    }

    // MARK: - Helpers
    private func springVelocity(distanceToTravel: CGFloat, gestureVelocity: CGFloat) -> CGFloat {
        distanceToTravel == 0 ? 0 : gestureVelocity / distanceToTravel
    }

    private func disableOtherTouches() {
        viewController.view.subviews.forEach {
            $0.isUserInteractionEnabled = false
        }
    }

    private func enableOtherTouches() {
        viewController.view.subviews.forEach {
            $0.isUserInteractionEnabled = true
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension StandardInteractionController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let scrollView = viewController.dismissalHandlingScrollView {
            return scrollView.contentOffset.y <= 0
        }

        return viewController.dismissalGestureEnabled
    }
}
