//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers class NCSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UINavigationControllerDelegate, UIGestureRecognizerDelegate {

    var placeholderViewController = UIViewController()

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

        placeholderViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "placeholderChatViewController")
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
            if let chatViewController = getActiveChatViewController() {
                chatViewController.leaveChat()
            }

            // Make sure the chatViewController gets properly deallocated
            setViewController(placeholderViewController, for: .secondary)
            navController.setViewControllers([placeholderViewController], animated: false)

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
            if !self.isCollapsed {
                // When another room is selected while there's still an active chatViewController
                // we need to make sure the active one is removed (applies to expanded mode only)
                if let navController = self.viewController(for: .secondary) as? UINavigationController {
                    navController.popToRootViewController(animated: false)
                }
            }

            super.showDetailViewController(vc, sender: sender)

            if self.isCollapsed {
                // Make sure we don't have accidentally a placeholderView in our navigation
                // while in collapsed mode
                if let navController = self.viewController(for: .secondary) as? UINavigationController,
                   vc is ChatViewController {

                    // Only set the viewController if there's actually an active one shown by showDetailViewController
                    // Otherwise UI might break or crash (view not loaded correctly)
                    // This might happen if a chatViewController is shown by a push notification
                    if self.hasActiveChatViewController() {
                        // First set the placeholderViewController, to make sure it is only referencing one navController
                        navController.setViewControllers([self.placeholderViewController], animated: false)
                        navController.setViewControllers([vc], animated: false)
                    }
                }
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            guard self.isCollapsed else { return }

            if let navController = self.viewController(for: .secondary) as? UINavigationController,
               let chatViewController = self.getActiveChatViewController() {

                // Make sure the navigationController has the correct reference to the chatViewController.
                // After a transition (eg. portrait to landscape) the navigationController still references the
                // the placeholderViewController in the navigationBar. When navigating back the app crashes in iOS 17,
                // because the navigationBar is referenced twice.
                navController.setViewControllers([self.placeholderViewController, chatViewController], animated: false)
                navController.setViewControllers([chatViewController], animated: false)
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
        if let navController = self.viewController(for: .secondary) as? UINavigationController {
            if hasActiveChatViewController() {

                // When we expand (show the second columns) and there's a active chatViewController
                // make sure we can drop back to the placeholderView
                navController.setViewControllers([placeholderViewController, getActiveChatViewController()!], animated: false)

            } else {
                navController.setViewControllers([placeholderViewController], animated: false)
            }
        }
    }

    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        if hasActiveChatViewController() {
            // If we collapse (only show one column) and there's a active chatViewController
            // make sure only have the chatViewController in the stack
            if let navController = self.viewController(for: .secondary) as? UINavigationController {
                navController.setViewControllers([getActiveChatViewController()!], animated: false)
            }
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

                // We also need to make sure, that the popToRootViewController animation is finished before setting the placeholderVC
                self.internalExecuteAfterTransition {
                    // Make sure the chatViewController gets properly deallocated
                    self.setViewController(self.placeholderViewController, for: .secondary)
                    navController.setViewControllers([self.placeholderViewController], animated: false)
                }
            }
        }
    }
}
