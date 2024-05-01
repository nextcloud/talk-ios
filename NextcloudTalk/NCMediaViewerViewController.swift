//
// Copyright (c) 2024 Marcel Müller <marcel.mueller@nextcloud.com>
//
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

import Foundation
import UIKit

@objcMembers class NCMediaViewerViewController: UIViewController,
                                                UIPageViewControllerDelegate,
                                                UIPageViewControllerDataSource,
                                                NCMediaViewerPageViewControllerDelegate {

    private let pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private var initialMessage: NCChatMessage

    private lazy var shareButton = {
        let shareButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)

        shareButton.isEnabled = false
        shareButton.primaryAction = UIAction(title: "", image: .init(systemName: "square.and.arrow.up"), handler: { [unowned self, unowned shareButton] _ in
            guard let mediaPageViewController = self.getCurrentPageViewController(),
                  let image = mediaPageViewController.currentImage
            else { return }

            let activityViewController = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            activityViewController.popoverPresentationController?.barButtonItem = shareButton

            self.present(activityViewController, animated: true)
        })

        return shareButton
    }()

    init(initialMessage: NCChatMessage) {
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
    }

    func setupNavigationBar() {
        let closeButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        closeButton.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.rightBarButtonItems = [closeButton]

        self.navigationController?.setToolbarHidden(false, animated: false)
        self.toolbarItems = [shareButton]
    }

    func getCurrentPageViewController() -> NCMediaViewerPageViewController? {
        return self.pageController.viewControllers?.first as? NCMediaViewerPageViewController
    }

    // MARK: - PageViewController delegate

    func getAllFileMessages() -> RLMResults<AnyObject> {
        let query = NSPredicate(format: "accountId = %@ AND token = %@ AND messageParametersJSONString contains[cd] %@", self.initialMessage.accountId, self.initialMessage.token, "\"file\":")
        let messages = NCChatMessage.objects(with: query).sortedResults(usingKeyPath: "messageId", ascending: true)

        return messages
    }

    func getPreviousFileMessage(from message: NCChatMessage) -> NCChatMessage? {
        let prevQuery = NSPredicate(format: "messageId < %ld", message.messageId)
        let messageObject = self.getAllFileMessages().objects(with: prevQuery).lastObject()

        if let message = messageObject as? NCChatMessage {
            if NCUtils.isImage(fileType: message.file().mimetype) {
                return message
            }

            // The current message contains a file, but not an image -> try to find another message
            return self.getPreviousFileMessage(from: message)
        }

        return nil
    }

    func getNextFileMessage(from message: NCChatMessage) -> NCChatMessage? {
        let prevQuery = NSPredicate(format: "messageId > %ld", message.messageId)
        let messageObject = self.getAllFileMessages().objects(with: prevQuery).firstObject()

        if let message = messageObject as? NCChatMessage {
            if NCUtils.isImage(fileType: message.file().mimetype) {
                return message
            }

            // The current message contains a file, but not an image -> try to find another message
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

        self.shareButton.isEnabled = (mediaPageViewController.currentImage != nil)
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

    func mediaViewerPageImageDidLoad(_ controller: NCMediaViewerPageViewController) {
        if let mediaPageViewController = self.getCurrentPageViewController(), mediaPageViewController.isEqual(controller) {
            self.shareButton.isEnabled = true
        }
    }
}
