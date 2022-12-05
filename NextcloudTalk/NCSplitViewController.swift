//
// Copyright (c) 2022 Claudio Cambra <claudio.cambra@gmail.com>
//
// Author Claudio Cambra <claudio.cambra@gmail.com>
// Author Marcel Müller <marcel.mueller@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

@objcMembers class NCSplitViewController: UISplitViewController, UISplitViewControllerDelegate, UINavigationControllerDelegate {

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
        }
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        self.internalExecuteAfterTransition {
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
                   vc is NCChatViewController {

                    // Only set the viewController if there's actually an active one shown by showDetailViewController
                    // Otherwise UI might break or crash (view not loaded correctly)
                    // This might happen if a chatViewController is shown by a push notification
                    if self.hasActiveChatViewController() {
                        navController.setViewControllers([vc], animated: false)
                    }
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

    func hasActiveChatViewController() -> Bool {
        return getActiveChatViewController() != nil
    }

    func getActiveChatViewController() -> NCChatViewController? {
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
        if let navController = self.viewController(for: .secondary) as? UINavigationController {
            if let chatViewController = getActiveChatViewController() {
                chatViewController.leaveChat()
            }

            // No animation -> animated would interfere with room highlighting
            navController.popToRootViewController(animated: false)

            // Make sure the chatViewController gets properly deallocated
            setViewController(placeholderViewController, for: .secondary)
            navController.setViewControllers([placeholderViewController], animated: false)
        }
    }
}
