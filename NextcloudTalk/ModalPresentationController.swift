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

class ModalPresentationController: UIPresentationController {

    lazy var fadeView = {
        let view = UIView()
        view.backgroundColor = .black.withAlphaComponent(0.5)
        view.alpha = 0.0
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    override func presentationTransitionWillBegin() {
        guard let containerView = containerView else { return }
        containerView.insertSubview(fadeView, at: 0)

        NSLayoutConstraint.activate([
            fadeView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            fadeView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            fadeView.topAnchor.constraint(equalTo: containerView.topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        guard let coordinator = presentedViewController.transitionCoordinator else {
            fadeView.alpha = 1.0
            return
        }

        coordinator.animate(alongsideTransition: { _ in
            self.fadeView.alpha = 1.0
        })
    }

    override func dismissalTransitionWillBegin() {
        guard let coordinator = presentedViewController.transitionCoordinator else {
            fadeView.alpha = 0.0
            return
        }

        if !coordinator.isInteractive {
            coordinator.animate(alongsideTransition: { _ in
                self.fadeView.alpha = 0.0
            })
        }
    }

    override func containerViewWillLayoutSubviews() {
        presentedView?.frame = frameOfPresentedViewInContainerView
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView else { return .zero }

        var safeAreaFrame = containerView.bounds.inset(by: containerView.safeAreaInsets)

        // In case we have a safe are at the top, we start our frame below it, but the bottom extends beyond the bottom safe area
        safeAreaFrame = CGRect(x: safeAreaFrame.minX, y: safeAreaFrame.minY, width: safeAreaFrame.width, height: containerView.frame.height - safeAreaFrame.minY)

        return safeAreaFrame
    }
}
