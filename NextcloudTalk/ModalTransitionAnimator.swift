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

class ModalTransitionAnimator: NSObject {

    private let presenting: Bool

    init(presenting: Bool) {
        self.presenting = presenting
        super.init()
    }
}

extension ModalTransitionAnimator: UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.5 }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if presenting {
            animatePresentation(using: transitionContext)
        } else {
            animateDismissal(using: transitionContext)
        }
    }

    private func animatePresentation(using transitionContext: UIViewControllerContextTransitioning) {
        let presentedViewController = transitionContext.viewController(forKey: .to)!
        transitionContext.containerView.addSubview(presentedViewController.view)

        let presentedFrame = transitionContext.finalFrame(for: presentedViewController)
        let dismissedFrame = CGRect(x: presentedFrame.minX, y: transitionContext.containerView.bounds.height, width: presentedFrame.width, height: presentedFrame.height)

        presentedViewController.view.frame = dismissedFrame

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), dampingRatio: 1.0) {
            presentedViewController.view.frame = presentedFrame
        }

        animator.addCompletion { _ in
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }

        animator.startAnimation()
    }

    private func animateDismissal(using transitionContext: UIViewControllerContextTransitioning) {
        let presentedViewController = transitionContext.viewController(forKey: .from)!
        let presentedFrame = transitionContext.finalFrame(for: presentedViewController)
        let dismissedFrame = CGRect(x: presentedFrame.minX, y: transitionContext.containerView.bounds.height, width: presentedFrame.width, height: presentedFrame.height)

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), dampingRatio: 1.0) {
            presentedViewController.view.frame = dismissedFrame
        }

        animator.addCompletion { _ in
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }

        animator.startAnimation()
    }
}
