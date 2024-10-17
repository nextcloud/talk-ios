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

        let timestamp = Date(timeIntervalSince1970: TimeInterval(self.initialMessage.timestamp))
        let dayTimeFormatter = DateFormatter()
        dayTimeFormatter.dateStyle = DateFormatter.Style.medium
        dayTimeFormatter.timeStyle = DateFormatter.Style.medium
        dayTimeFormatter.timeZone = .current
        let localDate = dayTimeFormatter.string(from: timestamp)
        self.navigationItem.titleView = setTitle(title: self.initialMessage.actorId, titleColor: UIColor.black, titleSize: 14, subtitle: localDate, subtitleSize: 12, view: self.view)
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

    func setTitle(title: String, titleColor: UIColor, titleSize: Int, subtitle: String, subtitleSize: Int, view: UIView) -> UIView {
       let titleLabel = UILabel(frame: CGRect(x: 40, y: -5, width: view.frame.width - 140, height: 20))

       titleLabel.backgroundColor = UIColor.clear
       titleLabel.textColor = titleColor
       titleLabel.adjustsFontSizeToFitWidth = false
       titleLabel.font = UIFont.boldSystemFont(ofSize: CGFloat(titleSize))
       titleLabel.lineBreakMode = .byTruncatingTail
       titleLabel.textAlignment = .center
       titleLabel.text = title
       let subtitleLabel = UILabel(frame: CGRect(x: 40, y: 18, width: view.frame.width - 140, height: 10))
       subtitleLabel.backgroundColor = UIColor.clear
       subtitleLabel.textColor = titleColor
       subtitleLabel.adjustsFontSizeToFitWidth = false
       subtitleLabel.lineBreakMode = .byTruncatingTail
       subtitleLabel.textAlignment = .center
       subtitleLabel.font = UIFont.systemFont(ofSize: CGFloat(subtitleSize))
       subtitleLabel.text = subtitle
       let titleView = UIView(frame: CGRect(x: 40, y: 0, width: view.frame.width - 30, height: 30))
       titleView.addSubview(titleLabel)
       titleView.addSubview(subtitleLabel)

       return titleView
   }
