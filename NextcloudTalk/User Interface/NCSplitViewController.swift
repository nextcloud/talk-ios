//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers class NCSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UINavigationControllerDelegate, UIGestureRecognizerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self
        self.preferredDisplayMode = .oneBesideSecondary

        // As we always show the columns on iPads, we don't need gesture support
        self.presentsWithGesture = false

        for viewController in self.viewControllers {
            if let navController = viewController as? UINavigationController {
                navController.delegate = self
            }
        }
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        if NCUtils.isiOSAppOnMac() {
            // When the app is running on MacOS there's a gap between the titleBar and the navigationBar.
            // We can remove that gap when setting a negative additionalSafeAreaInsets.top
            navigationController.additionalSafeAreaInsets.top = -navigationController.navigationBar.frame.maxY
        }

        if !isCollapsed {
            return
        }

        if let navController = self.viewController(for: .secondary) as? UINavigationController,
           viewController is RoomsTableViewController {

            // MovingFromParentViewController is always false in case of a rootViewController,
            // because of this, the chat will never be left in NCChatViewController
            // (see viewDidDisappear). So we have to leave the chat here, if collapsed
            getActiveChatViewController()?.leaveChat()

            // Make sure the chatViewController gets properly deallocated
            let placeholderViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "placeholderChatViewController")
            navController.setViewControllers([placeholderViewController], animated: false)

            let navController = UINavigationController(rootViewController: placeholderViewController)
            setViewController(navController, for: .secondary)

            // Instead of always allowing a gesture to be recognized, we need more control here.
            // See gestureRecognizerShouldBegin.
            navigationController.interactivePopGestureRecognizer?.delegate = self
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // We only want to recognize a "back gesture" through the interactivePopGestureRecognizer
        // when a chatViewController is shown. Otherwise (on the RoomsTableViewController)
        // recognizing a gesture might result in an unfinished transition and a broken UI
        if self.hasActiveChatViewController() {
            return true
        }

        return false
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        // Don't use internalExecuteAfterTransition here as that might interfere with presenting the CallViewController from CallKit/Background
        if !viewControllerToPresent.isBeingPresented {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
        }
    }

    override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        self.internalExecuteAfterTransition {
            if let vc = vc as? UINavigationController {
                super.showDetailViewController(vc, sender: sender)
            } else {
                // Create a new UINavigationController, to not stack up multiple view controllers
                let navController = UINavigationController(rootViewController: vc)
                super.showDetailViewController(navController, sender: sender)

                if #available(iOS 26.0, *) {
                    // Fix weird animation on iOS 26
                    vc.view.layoutIfNeeded()
                }
            }
        }
    }

    func internalExecuteAfterTransition(action: @escaping () -> Void) {
        if self.transitionCoordinator == nil {
            // No ongoing animations -> execute action directly
            action()
        } else {
            // Wait until the splitViewController finished all it's animations.
            // Otherwise this can lead to different UI glitches, for example a chatViewController might
            // end up in the wrong column. This mainly happens when being in a
            // conversation and tapping a push notification of another conversation.
            self.transitionCoordinator?.animate(alongsideTransition: nil, completion: { _ in
                DispatchQueue.main.async {
                    action()
                }
            })
        }
    }

    func showPlaceholderView() {
        // Safe-guard to not show a placeholder view while in collapsed mode
        if self.isCollapsed {
            return
        }

        let placeholderViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "placeholderChatViewController")
        self.showDetailViewController(placeholderViewController, sender: nil)
    }

    func hasActiveChatViewController() -> Bool {
        return getActiveChatViewController() != nil
    }

    func getActiveChatViewController() -> ChatViewController? {
        return getActiveViewController()
    }

    func getActiveViewController<T: UIViewController>() -> T? {
        // In case we have a collapsed view, we need to retrieve the viewController this way
        if let navController = self.viewController(for: .secondary) as? UINavigationController {
            for secondaryViewController in navController.viewControllers {
                if let activeViewController = secondaryViewController as? T {
                    return activeViewController
                }
            }
        }

        if let navController = self.viewController(for: .primary) as? UINavigationController {
            for primaryViewController in navController.viewControllers {
                if let activeViewController = primaryViewController as? T {
                    return activeViewController
                }
            }
        }

        return nil
    }

    func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column {
        // When we rotate the device and the splitViewController gets collapsed
        // we need to determine if we're still in a chat or not.
        // In case we are, we want to stay in the chat view, else we want to show the roomList
        if hasActiveChatViewController() {
            return .secondary
        }

        return .primary
    }

    func splitViewControllerDidExpand(_ svc: UISplitViewController) {
        if !hasActiveChatViewController() {
            // Set the placeholder view on expand again, to make sure the navigation bar is visible
            // E.g. Regular -> Join chat, move to compact, leave chat, move to regular again
            self.showPlaceholderView()
        }
    }

    func popSecondaryColumnToRootViewController() {
        self.internalExecuteAfterTransition {
            if let navController = self.viewController(for: .secondary) as? UINavigationController {
                if let chatViewController = self.getActiveChatViewController() {
                    chatViewController.leaveChat()
                }

                // No animation -> animated would interfere with room highlighting
                navController.popToRootViewController(animated: false)

                // This is needed, e.g. when leaving a room on an iPad to remove the chat view on the secondary column
                self.showPlaceholderView()
            }
        }
    }
}
