//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit

@objcMembers class NCMediaViewerViewController: UIViewController,
                                                UIPageViewControllerDelegate,
                                                UIPageViewControllerDataSource,
                                                NCMediaViewerPageViewControllerDelegate {

    private let room: NCRoom
    private let pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private var initialMessage: NCChatMessage

    private lazy var shareButton = {
        let shareButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        shareButton.isEnabled = false
        shareButton.primaryAction = UIAction(title: "", image: .init(systemName: "square.and.arrow.up"), handler: { [unowned self, unowned shareButton] _ in
            guard let mediaPageViewController = self.getCurrentPageViewController() else { return }

            var itemsToShare: [Any] = []

            if let image = mediaPageViewController.currentImage {
                itemsToShare.append(image)
            } else if let videoURL = mediaPageViewController.currentVideoURL {
                itemsToShare.append(videoURL)
            } else {
                return
            }
            let activityViewController = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
            activityViewController.popoverPresentationController?.barButtonItem = shareButton

            self.present(activityViewController, animated: true)
        })

        return shareButton
    }()

    private lazy var showMessageButton = {
        let showMessageButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        showMessageButton.isEnabled = false
        showMessageButton.primaryAction = UIAction(title: "", image: .init(systemName: "text.magnifyingglass"), handler: { [unowned self] _ in
            guard let mediaPageViewController = self.getCurrentPageViewController() else { return }

            let message = mediaPageViewController.message

            if let account = message.account, let chatViewController = ContextChatViewController(forRoom: self.room, withAccount: account, withMessage: [], withHighlightId: 0) {
                chatViewController.showContext(ofMessageId: message.messageId, withLimit: 50, withCloseButton: true)

                let navController = NCNavigationController(rootViewController: chatViewController)
                self.present(navController, animated: true)
            }

        })

        return showMessageButton
    }()

    init(initialMessage: NCChatMessage, room: NCRoom) {
        self.room = room
        self.initialMessage = initialMessage

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        NCAppBranding.styleViewController(self)

        self.view.backgroundColor = .systemBackground
        self.setupNavigationBar()

        self.pageController.delegate = self
        self.pageController.dataSource = self
        self.pageController.view.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.pageController.view)

        NSLayoutConstraint.activate([
            self.pageController.view.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor),
            self.pageController.view.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor),
            self.pageController.view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.pageController.view.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
        ])

        self.pageController.didMove(toParent: self)

        let initialViewController = NCMediaViewerPageViewController(message: self.initialMessage)
        initialViewController.delegate = self
        self.pageController.setViewControllers([initialViewController], direction: .forward, animated: false)

        self.navigationItem.title = initialViewController.navigationItem.title

        AllocationTracker.shared.addAllocation("NCMediaViewerViewController")
    }

    deinit {
        AllocationTracker.shared.removeAllocation("NCMediaViewerViewController")
    }

    func setupNavigationBar() {
        let closeButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        closeButton.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.rightBarButtonItems = [closeButton]

        self.navigationController?.setToolbarHidden(false, animated: false)

        let appearance = UIToolbarAppearance()
        appearance.backgroundColor = .secondarySystemBackground

        self.navigationController?.toolbar.standardAppearance = appearance
        self.navigationController?.toolbar.compactAppearance = appearance
        self.navigationController?.toolbar.scrollEdgeAppearance = appearance

        let fixedSpace = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        fixedSpace.width = 20
        self.toolbarItems = [shareButton, fixedSpace, showMessageButton]
    }

    func getCurrentPageViewController() -> NCMediaViewerPageViewController? {
        return self.pageController.viewControllers?.first as? NCMediaViewerPageViewController
    }

    // MARK: - PageViewController delegate

    func getAllFileMessages() -> RLMResults<AnyObject>? {
        guard let accountId = self.initialMessage.accountId else { return nil }

        let query = NSPredicate(format: "accountId = %@ AND token = %@ AND messageParametersJSONString contains[cd] %@", accountId, self.initialMessage.token, "\"file\":")
        let messages = NCChatMessage.objects(with: query).sortedResults(usingKeyPath: "messageId", ascending: true)

        return messages
    }

    func getPreviousFileMessage(from message: NCChatMessage) -> NCChatMessage? {
        let prevQuery = NSPredicate(format: "messageId < %ld", message.messageId)

        guard let queriedObjects = self.getAllFileMessages()?.objects(with: prevQuery) else { return nil }
        let messageObject = queriedObjects.lastObject()

        if let message = messageObject as? NCChatMessage {
            guard let filePath = message.file().path else {
                return self.getPreviousFileMessage(from: message)
            }

            let fileType = message.file()?.mimetype ?? ""
            let isSupportedMedia = NCUtils.isImage(fileType: fileType) || NCUtils.isVideo(fileType: fileType)
            let isUnsupportedExtension = VLCKitVideoViewController.supportedFileExtensions.contains(URL(fileURLWithPath: filePath).pathExtension.lowercased())

            if isSupportedMedia && !isUnsupportedExtension {
                return message
            }

            return self.getPreviousFileMessage(from: message)
        }

        return nil
    }

    func getNextFileMessage(from message: NCChatMessage) -> NCChatMessage? {
        let prevQuery = NSPredicate(format: "messageId > %ld", message.messageId)

        guard let messageObject = self.getAllFileMessages()?.objects(with: prevQuery).firstObject() else { return nil }

        if let message = messageObject as? NCChatMessage {
            guard let filePath = message.file().path else {
                return self.getNextFileMessage(from: message)
            }

            let fileType = message.file()?.mimetype ?? ""
            let isSupportedMedia = NCUtils.isImage(fileType: fileType) || NCUtils.isVideo(fileType: fileType)
            let isUnsupportedExtension = VLCKitVideoViewController.supportedFileExtensions.contains(URL(fileURLWithPath: filePath).pathExtension.lowercased())

            if isSupportedMedia && !isUnsupportedExtension {
                return message
            }

            return self.getNextFileMessage(from: message)
        }

        return nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let prevMediaPageVC = viewController as? NCMediaViewerPageViewController,
              let prevMessage = self.getPreviousFileMessage(from: prevMediaPageVC.message)
        else { return nil }

        let mediaPageViewController = NCMediaViewerPageViewController(message: prevMessage)
        mediaPageViewController.delegate = self
        return mediaPageViewController
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let prevMediaPageVC = viewController as? NCMediaViewerPageViewController,
              let nextMessage = self.getNextFileMessage(from: prevMediaPageVC.message)
        else { return nil }

        let mediaPageViewController = NCMediaViewerPageViewController(message: nextMessage)
        mediaPageViewController.delegate = self
        return mediaPageViewController
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        // Update the titel of the currently shown viewController
        guard let mediaPageViewController = self.getCurrentPageViewController() else { return }
        self.navigationItem.title = mediaPageViewController.navigationItem.title

        self.shareButton.isEnabled = (mediaPageViewController.currentImage != nil) || (mediaPageViewController.currentVideoURL != nil)
        self.showMessageButton.isEnabled = (mediaPageViewController.currentImage != nil) || (mediaPageViewController.currentVideoURL != nil)
    }

    // MARK: - NCMediaViewerPageViewController delegate

    func mediaViewerPageZoomDidChange(_ controller: NCMediaViewerPageViewController, _ scale: Double) {
        // Prevent the scrollView interfering with our pan gesture recognizer when the view is zoomed
        // Also disable dismissal gesture when the view is zoomed

        guard let navController = self.navigationController as? CustomPresentableNavigationController else { return }

        if scale == 1 {
            pageController.enableSwipeGesture()
            navController.dismissalGestureEnabled = true
        } else {
            pageController.disableSwipeGesture()
            navController.dismissalGestureEnabled = false
        }
    }

    func mediaViewerPageMediaDidLoad(_ controller: NCMediaViewerPageViewController) {
        if let mediaPageViewController = self.getCurrentPageViewController(), mediaPageViewController.isEqual(controller) {
            self.shareButton.isEnabled = true
            self.showMessageButton.isEnabled = true
        }
    }
}
