//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    public var window: UIWindow?

    private var debugLabel: UILabel?
    private var debugLabelTimer: Timer?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // The window and its root view controller come from the storyboard named by UISceneStoryboardFile,
        // so they already exist by the time this is called
        NCUserInterfaceController.sharedInstance().mainViewController = self.window?.rootViewController as? NCSplitViewController
        NCUserInterfaceController.sharedInstance().roomsTableViewController = NCUserInterfaceController.sharedInstance().mainViewController.viewControllers.first?.children.first as? RoomsTableViewController
        NCUserInterfaceController.sharedInstance().mainViewController.displayModeButtonVisibility = .never

        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-TestEnvironment") {
            let mainView: UIView = NCUserInterfaceController.sharedInstance().mainViewController.view

            let debugLabel = UILabel(frame: CGRect(x: 20, y: 30, width: 200, height: 20))
            debugLabel.font = .systemFont(ofSize: UIFont.smallSystemFontSize)
            debugLabel.translatesAutoresizingMaskIntoConstraints = false
            self.debugLabel = debugLabel

            mainView.addSubview(debugLabel)
            NSLayoutConstraint.activate([
                debugLabel.topAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.topAnchor, constant: -15),
                debugLabel.leadingAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.leadingAnchor, constant: 5),
                debugLabel.trailingAnchor.constraint(equalTo: mainView.safeAreaLayoutGuide.trailingAnchor)
            ])

            self.debugLabelTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.debugLabel?.text = AllocationTracker.shared.description
            }
        }

        // On a cold launch the URL or user activity that started the app arrives here rather than through the
        // scene(_:openURLContexts:) / scene(_:continue:) callbacks below
        self.open(connectionOptions.urlContexts)

        if let userActivity = connectionOptions.userActivities.first {
            self.scene(scene, continue: userActivity)
        }
    }

    // MARK: - URLs and user activities
    //
    // Once a scene delegate exists, UIKit stops calling application(_:open:options:) and
    // application(_:continue:restorationHandler:), so deep links and Siri call intents have to be picked up here. The
    // handling itself is unchanged and still lives on AppDelegate.

    func scene(_ scene: UIScene, openURLContexts urlContexts: Set<UIOpenURLContext>) {
        self.open(urlContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        _ = appDelegate.application(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
    }

    private func open(_ urlContexts: Set<UIOpenURLContext>) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        for context in urlContexts {
            _ = appDelegate.application(UIApplication.shared, open: context.url, options: [:])
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Invalidate a potentially existing label timer
        self.debugLabelTimer?.invalidate()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Sent when the scene is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of sceneWillDisconnect: when the user quits.

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        appDelegate.keepExternalSignalingConnectionAliveTemporarily()
        appDelegate.scheduleAppRefresh()
        appDelegate.scheduleBackgroundProcessing()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Restart any tasks that were paused (or not yet started) while the scene was inactive. If the scene was previously in the background, optionally refresh the user interface.

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

        appDelegate.checkForDisconnectedExternalSignalingConnection()

        NCNotificationController.sharedInstance().removeAllNotifications(forAccountId: NCDatabaseManager.sharedInstance().activeAccount().accountId)
    }
}
