//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import NextcloudKit
import QuickLook
import SwiftyAttributes
import TOCropViewController
import AVFoundation
import MBProgressHUD

@objc public protocol ShareConfirmationViewControllerDelegate {
    @objc func shareConfirmationViewControllerDidFail(_ viewController: ShareConfirmationViewController)
    @objc func shareConfirmationViewControllerDidFinish(_ viewController: ShareConfirmationViewController)
    @objc func shareConfirmationViewControllerDidCancel(_ viewController: ShareConfirmationViewController)
}

@objcMembers public class ShareConfirmationViewController: InputbarViewController,
                                                           NKCommonDelegate,
                                                           ShareItemControllerDelegate,
                                                           UIImagePickerControllerDelegate,
                                                           UIDocumentPickerDelegate,
                                                           UINavigationControllerDelegate,
                                                           UICollectionViewDelegateFlowLayout,
                                                           TOCropViewControllerDelegate,
                                                           QLPreviewControllerDataSource,
                                                           QLPreviewControllerDelegate {

    // MARK: - Public var

    public var isModal: Bool = false
    public var forwardingMessage: Bool = false

    public weak var delegate: ShareConfirmationViewControllerDelegate?

    public lazy var shareItemController: ShareItemController = {
        let controller = ShareItemController()
        controller.delegate = self

        return controller
    }()

    // MARK: - Private var

    private var serverCapabilities: ServerCapabilities
    private var shareType: ShareConfirmationType = .item
    private var shareContentView = UIView()
    private var shareSilently = false
    private var imagePicker: UIImagePickerController?
    private var hud: MBProgressHUD?
    private var objectShareMessage: NCChatMessage?
    private var uploadGroup = DispatchGroup()
    private var uploadFailed = false
    private var uploadErrors: [String] = []
    private var uploadSuccess: [ShareItem] = []

    private enum ShareConfirmationType {
        case text
        case item
        case objectShare
    }

    // MARK: - UI Controls

    private lazy var sendButton: UIBarButtonItem = {
        let sendButton = UIBarButtonItem(title: NSLocalizedString("Send", comment: ""), style: .done, target: self, action: #selector(sendButtonPressed))
        sendButton.accessibilityHint = NSLocalizedString("Double tap to share with selected conversations", comment: "")
        return sendButton
    }()

    private lazy var sharingIndicatorView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView()
        indicator.color = NCAppBranding.themeTextColor()

        return indicator
    }()

    private lazy var toLabel: UILabel = {
        var label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var toLabelView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground
        view.addSubview(self.toLabel)

        NSLayoutConstraint.activate([
            self.toLabel.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 20),
            self.toLabel.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -20),
            self.toLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            self.toLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        return view
    }()

    private lazy var itemToolbar: UIToolbar = {
        let toolbar = UIToolbar(frame: .init(x: 0, y: 0, width: 100, height: 44))

        toolbar.barTintColor = .systemGroupedBackground
        toolbar.isTranslucent = false

        if #unavailable(iOS 26) {
            toolbar.setItems([removeItemButton, UIBarButtonItem(systemItem: .flexibleSpace), cropItemButton, previewItemButton, addItemButton], animated: false)
        } else {
            toolbar.setItems([UIBarButtonItem(systemItem: .flexibleSpace), removeItemButton, UIBarButtonItem(systemItem: .fixedSpace), cropItemButton, previewItemButton, addItemButton], animated: false)
        }

        toolbar.translatesAutoresizingMaskIntoConstraints = false

        return toolbar
    }()

    private lazy var removeItemButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .init(systemName: "trash"))
        button.width = 56
        button.target = self
        button.action = #selector(removeItemButtonPressed)

        return button
    }()

    private lazy var cropItemButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .init(systemName: "crop.rotate"))
        button.width = 56
        button.target = self
        button.action = #selector(cropItemButtonPressed)

        return button
    }()

    private lazy var previewItemButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .init(systemName: "eye"))
        button.width = 56
        button.target = self
        button.action = #selector(previewItemButtonPressed)

        return button
    }()

    private lazy var addItemButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: .init(systemName: "plus"))
        button.width = 56

        var items: [UIAction] = []

        let cameraAction = UIAction(title: NSLocalizedString("Camera", comment: ""), image: UIImage(systemName: "camera")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.checkAndPresentCamera()
        }

        let photoLibraryAction = UIAction(title: NSLocalizedString("Photo Library", comment: ""), image: UIImage(systemName: "photo")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentPhotoLibrary()
        }

        let filesAction = UIAction(title: NSLocalizedString("Files", comment: ""), image: UIImage(systemName: "doc")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentDocumentPicker()
        }

#if !APP_EXTENSION
        // Camera access is not available in app extensions
        // https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            items.append(cameraAction)
        }
#endif

        items.append(photoLibraryAction)
        items.append(filesAction)

        button.menu = UIMenu(children: items)

        return button
    }()

    private lazy var shareCollectionViewLayout: UICollectionViewFlowLayout = {
        // Make sure that we use a layout that invalidates itself when the bounds changed
        let layout = BoundsChangedFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        return layout
    }()

    private lazy var shareCollectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .init(x: 0, y: 0, width: 10, height: 10), collectionViewLayout: self.shareCollectionViewLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .systemGroupedBackground
        return collectionView
    }()

    private lazy var shareTextView: UITextView = {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isHidden = true
        return textView
    }()

    private lazy var pageControl: UIPageControl = {
        let pageControl = UIPageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.currentPageIndicatorTintColor = NCAppBranding.elementColor()
        pageControl.pageIndicatorTintColor = NCAppBranding.placeholderColor()
        pageControl.hidesForSinglePage = true
        pageControl.numberOfPages = 1
        pageControl.addTarget(self, action: #selector(pageControlValueChanged), for: .valueChanged)

        return pageControl
    }()

    // MARK: - Init.

    public init?(room: NCRoom, thread: NCThread?, account: TalkAccount, serverCapabilities: ServerCapabilities) {
        self.serverCapabilities = serverCapabilities

        super.init(forRoom: room, withAccount: account, withView: self.shareContentView)
        self.thread = thread

        self.shareContentView.addSubview(self.shareCollectionView)
        self.shareContentView.addSubview(self.pageControl)
        self.shareContentView.addSubview(self.shareTextView)
        self.shareContentView.addSubview(self.itemToolbar)

        NSLayoutConstraint.activate([
            self.shareTextView.leftAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leftAnchor, constant: 20),
            self.shareTextView.rightAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.rightAnchor, constant: -20),
            self.shareTextView.bottomAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])

        NSLayoutConstraint.activate([
            self.itemToolbar.leftAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leftAnchor),
            self.itemToolbar.rightAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.rightAnchor),
            self.itemToolbar.heightAnchor.constraint(equalToConstant: 44)
        ])

        if #unavailable(iOS 26) {
            self.shareContentView.addSubview(self.toLabelView)

            NSLayoutConstraint.activate([
                self.toLabelView.leftAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leftAnchor),
                self.toLabelView.rightAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.rightAnchor),
                self.toLabelView.topAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.topAnchor),
                self.toLabelView.heightAnchor.constraint(equalToConstant: 36),

                self.shareTextView.topAnchor.constraint(equalTo: self.toLabelView.bottomAnchor, constant: 20),

                self.itemToolbar.topAnchor.constraint(equalTo: self.toLabelView.bottomAnchor)
            ])
        } else {
            // On iOS 26 we don't have a toLabel anymore, so we need to constraint to the safe area as well
            NSLayoutConstraint.activate([
                self.shareTextView.topAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.topAnchor),

                self.itemToolbar.topAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.topAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            self.shareCollectionView.leftAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leftAnchor),
            self.shareCollectionView.rightAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.rightAnchor),
            self.shareCollectionView.topAnchor.constraint(equalTo: self.itemToolbar.bottomAnchor, constant: 8),
            self.shareCollectionView.bottomAnchor.constraint(equalTo: self.pageControl.topAnchor, constant: -8),

            self.pageControl.leftAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leftAnchor),
            self.pageControl.rightAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.rightAnchor),
            self.pageControl.heightAnchor.constraint(equalToConstant: 26),
            self.pageControl.bottomAnchor.constraint(equalTo: self.textInputbar.topAnchor)
        ])
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func shareText(_ sharedText: String) {
        self.shareType = .text

        DispatchQueue.main.async {
            self.setTextInputbarHidden(true, animated: false)
            self.shareCollectionView.isHidden = true
            self.itemToolbar.isHidden = true
            self.shareTextView.isHidden = false
            self.shareTextView.text = sharedText

            // When an item of type "public.url" or "public.plain-text" is shared,
            // we switch to text-sharing after viewWillAppear, so we need to add the sendButton here as well
            self.navigationItem.rightBarButtonItem = self.sendButton

            if #unavailable(iOS 26.0) {
                self.navigationItem.rightBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
            }
        }
    }

    public func shareObjectShareMessage(_ objectShareMessage: NCChatMessage) {
        self.shareType = .objectShare

        DispatchQueue.main.async {
            self.setTextInputbarHidden(true, animated: false)
            self.shareCollectionView.isHidden = true
            self.itemToolbar.isHidden = true
            self.shareTextView.isHidden = false
            self.shareTextView.isUserInteractionEnabled = false
            self.shareTextView.text = objectShareMessage.parsedMessage().string
            self.objectShareMessage = objectShareMessage
        }
    }

    // MARK: - View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Configure communication lib
        let userToken = NCKeyChainController.sharedInstance().token(forAccountId: self.account.accountId)
        let userAgent = "Mozilla/5.0 (iOS) Nextcloud-Talk v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "Unknown")"

        NextcloudKit.shared.setup(account: self.account.accountId,
                                  user: self.account.user,
                                  userId: self.account.userId,
                                  password: userToken,
                                  urlBase: self.account.server,
                                  userAgent: userAgent,
                                  nextcloudVersion: self.serverCapabilities.versionMajor,
                                  delegate: self)

        if #unavailable(iOS 26) {
            let localizedToString = NSLocalizedString("To:", comment: "TRANSLATORS this is for sending something 'to' a user. E.g. 'To: John Doe'")
            let toString = localizedToString.withFont(.boldSystemFont(ofSize: 15)).withTextColor(.tertiaryLabel)
            let roomString = self.room.displayName.withFont(.systemFont(ofSize: 15)).withTextColor(.label)
            self.toLabel.attributedText = toString + NSAttributedString(string: " ") + roomString
        } else {
            self.navigationItem.title = self.room.displayName
        }

        let bundle = Bundle(for: ShareConfirmationCollectionViewCell.self)
        self.shareCollectionView.register(UINib(nibName: kShareConfirmationTableCellNibName, bundle: bundle), forCellWithReuseIdentifier: kShareConfirmationCellIdentifier)
        self.shareCollectionView.delegate = self
    }

    public override func viewWillAppear(_ animated: Bool) {
        // Add the cancel button in viewWillAppear, so that the caller can change the isModal property after initialization
        if self.isModal {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
            cancelButton.accessibilityHint = NSLocalizedString("Double tap to dismiss sharing options", comment: "")

            self.navigationItem.leftBarButtonItem = cancelButton
            self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        }

        var captionAllowed = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityMediaCaption, forAccountId: account.accountId)
        captionAllowed = captionAllowed && self.shareType == .item

        if !captionAllowed {
            self.navigationItem.rightBarButtonItem = self.sendButton
            self.navigationItem.rightBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
            self.setTextInputbarHidden(true, animated: false)
        } else {
            let silentSendAction = UIAction(title: NSLocalizedString("Send without notification", comment: ""), image: UIImage(systemName: "bell.slash")) { [unowned self] _ in
                self.silentSendPressed()
            }

            self.rightButton.menu = UIMenu(children: [silentSendAction])
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if self.shareType == .text {
            // When we are sharing a text, we want to start editing right away
            self.shareTextView.becomeFirstResponder()
        }
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if self.shareType == .text {
            return
        }

        self.shareCollectionView.isHidden = true

        // Invalidate layout to remove warning about item size must be less than UICollectionView
        self.shareCollectionView.collectionViewLayout.invalidateLayout()
        let currentItem = self.getCurrentShareItem()

        coordinator.animate { _ in
            // Invalidate the view now so cell size is correctly calculated
            // The size of the collection view is correct at this moment
            self.shareCollectionView.collectionViewLayout.invalidateLayout()
        } completion: { _ in
            // Scroll to the element and make collection view appear
            if let currentItem {
                self.scroll(to: currentItem, animated: false)
            }

            self.shareCollectionView.isHidden = false
        }
    }

    override func setTitleView() {
        // We don't want a titleView in this case
    }

    public override func canPressRightButton() -> Bool {
        // We want to allow sending pictures even when no text is entered
        return !self.shareItemController.shareItems.isEmpty
    }

    // MARK: - Button Actions

    func removeItemButtonPressed() {
        if let item = self.getCurrentShareItem() {
            self.shareItemController.remove(item)
        }
    }

    func cropItemButtonPressed() {
        if let item = self.getCurrentShareItem(),
           let image = self.shareItemController.getImageFrom(item) {

            let cropViewController = TOCropViewController(image: image)
            cropViewController.delegate = self
            self.present(cropViewController, animated: true)
        }
    }

    func previewItemButtonPressed() {
        self.previewCurrentItem()
    }

    func cancelButtonPressed() {
        self.delegate?.shareConfirmationViewControllerDidCancel(self)
    }

    func sendButtonPressed() {
        self.sendCurrent(silently: false)
    }

    public override func didPressRightButton(_ sender: Any?) {
        self.sendCurrent(silently: false)
    }

    func silentSendPressed() {
        self.sendCurrent(silently: true)
    }

    func sendCurrent(silently: Bool) {
        self.shareSilently = silently

        if self.shareType == .text {
            self.sendSharedText()
        } else if self.shareType == .objectShare {
            self.sendObjectShare()
        } else {
            self.uploadAndShareFiles()
        }

        self.startAnimatingSharingIndicator()
    }

    // MARK: - Add additional items

    func checkAndPresentCamera() {
        // https://stackoverflow.com/a/20464727/2512312
        let mediaType = AVMediaType.video
        let authStatus = AVCaptureDevice.authorizationStatus(for: mediaType)

        if authStatus == AVAuthorizationStatus.authorized {
            self.presentCamera()
            return
        } else if authStatus == AVAuthorizationStatus.notDetermined {
            AVCaptureDevice.requestAccess(for: mediaType, completionHandler: { (granted: Bool) in
                if granted {
                    self.presentCamera()
                }
            })
            return
        }

        let alert = UIAlertController(title: NSLocalizedString("Could not access camera", comment: ""),
                                      message: NSLocalizedString("Camera access is not allowed. Check your settings.", comment: ""),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        self.present(alert, animated: true)
    }

    func presentCamera() {
        DispatchQueue.main.async {
            self.imagePicker = UIImagePickerController()

            if let imagePicker = self.imagePicker,
               let sourceType = UIImagePickerController.availableMediaTypes(for: imagePicker.sourceType) {
                imagePicker.sourceType = .camera
                imagePicker.cameraFlashMode = UIImagePickerController.CameraFlashMode(rawValue: NCUserDefaults.preferredCameraFlashMode()) ?? .off
                imagePicker.mediaTypes = sourceType
                imagePicker.delegate = self
                self.present(imagePicker, animated: true)
            }
        }
    }

    func presentPhotoLibrary() {
        self.imagePicker = UIImagePickerController()

        if let imagePicker = self.imagePicker {
            imagePicker.sourceType = .photoLibrary
            imagePicker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary) ?? []
            imagePicker.delegate = self
            self.present(imagePicker, animated: true)
        }
    }

    func presentDocumentPicker() {
        DispatchQueue.main.async {
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            documentPicker.delegate = self
            self.present(documentPicker, animated: true)
        }
    }

    // MARK: - Actions

    func sendSharedText() {
        NCAPIController.sharedInstance().sendChatMessage(self.shareTextView.text, toRoom: self.room.token, threadTitle: nil, replyTo: -1, referenceId: nil, silently: false, for: self.account) { error in
            if let error {
                NCUtils.log(String(format: "Failed to share text. Error: %@", error.localizedDescription))
                self.delegate?.shareConfirmationViewControllerDidFail(self)
            } else {
                NCIntentController.sharedInstance().donateSendMessageIntent(for: self.room)
                self.delegate?.shareConfirmationViewControllerDidFinish(self)
            }

            self.stopAnimatingSharingIndicator()
        }
    }

    func sendObjectShare() {
        NCAPIController.sharedInstance().shareRichObject(self.objectShareMessage?.richObjectFromObjectShare, inRoom: self.room.token, for: self.account) { error in
            if let error {
                NCUtils.log(String(format: "Failed to share rich object. Error: %@", error.localizedDescription))
                self.delegate?.shareConfirmationViewControllerDidFail(self)
            } else {
                NCIntentController.sharedInstance().donateSendMessageIntent(for: self.room)
                self.delegate?.shareConfirmationViewControllerDidFinish(self)
            }
            self.stopAnimatingSharingIndicator()
        }
    }

    func updateHudProgress() {
        guard let hud = self.hud else { return }

        DispatchQueue.main.async {
            var progress: CGFloat = 0.0
            var items = 0

            for shareItem in self.shareItemController.shareItems {
                progress += shareItem.uploadProgress
                items += 1
            }

            hud.progress = Float(progress / CGFloat(items))
        }
    }

    func uploadAndShareFiles() {
        // TODO: This has no effect on ShareExtension
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "uploadAndShareFiles")

        // Hide keyboard before upload to correctly display the HUD
        self.textView.resignFirstResponder()

        NCIntentController.sharedInstance().donateSendMessageIntent(for: self.room)

        self.hud = MBProgressHUD.showAdded(to: self.view, animated: true)
        self.hud?.mode = .annularDeterminate
        self.hud?.label.text = String(format: NSLocalizedString("Uploading %ld elements", comment: ""), self.shareItemController.shareItems.count)

        if self.shareItemController.shareItems.count == 1 {
            self.hud?.label.text = NSLocalizedString("Uploading 1 element", comment: "")
        }

        self.uploadGroup = DispatchGroup()
        self.uploadErrors = []
        self.uploadSuccess = []

        // Add caption to last shareItem
        if let shareItem = self.shareItemController.shareItems.last {
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityMediaCaption, forAccountId: self.account.accountId) {
                let messageParameters = NCMessageParameter.messageParametersJSONString(from: self.mentionsDict) ?? ""
                let message = NCChatMessage()
                message.message = self.replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: self.textView.text, parameters: messageParameters)
                message.messageParametersJSONString = messageParameters

                shareItem.caption = message.sendingMessage
            }
        }

        for shareItem in self.shareItemController.shareItems {
            NSLog("Uploading \(shareItem.fileURL.absoluteString)")

            self.uploadGroup.enter()

            NCAPIController.sharedInstance().uniqueNameForFileUpload(withName: shareItem.fileName, originalName: true, for: self.account) { fileServerURL, fileServerPath, _, errorDescription in
                if let fileServerURL, let fileServerPath {
                    self.uploadFile(to: fileServerURL, with: fileServerPath, with: shareItem)
                } else {
                    NCUtils.log(String(format: "Error finding unique upload name. Error: %@", errorDescription ?? "Unknown error"))
                    self.uploadErrors.append(errorDescription ?? "Unknown error")
                    self.uploadGroup.leave()
                }
            }
        }

        self.uploadGroup.notify(queue: .main) {
            self.stopAnimatingSharingIndicator()
            self.hud?.hide(animated: true)

            // TODO: Do error reporting per item
            if self.uploadErrors.isEmpty {
                self.shareItemController.removeAllItems()
                self.delegate?.shareConfirmationViewControllerDidFinish(self)
            } else {
                // We remove the successfully uploaded items, so only the failed ones are kept
                self.shareItemController.remove(self.uploadSuccess)

                let alert = UIAlertController(title: NSLocalizedString("Upload failed", comment: ""),
                                              message: self.uploadErrors.joined(separator: "\n"),
                                              preferredStyle: .alert)

                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))

                self.present(alert, animated: true)
            }

            bgTask.stopBackgroundTask()
        }
    }

    func uploadFile(to fileServerURL: String, with filePath: String, with item: ShareItem) {
        NextcloudKit.shared.upload(serverUrlFileName: fileServerURL, fileNameLocalPath: item.filePath) { _ in
            NSLog("Upload task")
        } progressHandler: { progress in
            item.uploadProgress = progress.fractionCompleted
            self.updateHudProgress()
        } completionHandler: { _, _, _, _, _, _, nkError in
            if nkError.errorCode == 0 {
                var talkMetaData: [String: Any] = [:]

                let itemCaption = item.caption.trimmingCharacters(in: .whitespaces)
                if !itemCaption.isEmpty {
                    talkMetaData["caption"] = itemCaption
                }

                if self.shareSilently {
                    talkMetaData["silent"] = self.shareSilently
                }

                if let thread = self.thread {
                    talkMetaData["threadId"] = thread.threadId
                }

                NCAPIController.sharedInstance().shareFileOrFolder(for: self.account, atPath: filePath, toRoom: self.room.token, talkMetaData: talkMetaData, referenceId: nil) { error in
                    if let error {
                        NCUtils.log(String(format: "Failed to share file. Error: %@", error.localizedDescription))
                        self.uploadErrors.append(error.localizedDescription)
                    } else {
                        self.uploadSuccess.append(item)
                    }

                    self.uploadGroup.leave()
                }
            } else if nkError.errorCode == 404 || nkError.errorCode == 409 {
                NCAPIController.sharedInstance().checkOrCreateAttachmentFolder(for: self.account) { created, _ in
                    if created {
                        self.uploadFile(to: fileServerURL, with: filePath, with: item)
                    } else {
                        self.uploadErrors.append(nkError.errorDescription)
                        self.uploadGroup.leave()
                    }
                }
            } else {
                NCUtils.log(String(format: "Failed to upload file. Error: %@", nkError.errorDescription))
                self.uploadErrors.append(nkError.errorDescription)
                self.uploadGroup.leave()
            }
        }
    }

    // MARK: - User Interface

    func startAnimatingSharingIndicator() {
        DispatchQueue.main.async {
            self.sharingIndicatorView.startAnimating()
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.sharingIndicatorView)
        }
    }

    func stopAnimatingSharingIndicator() {
        DispatchQueue.main.async {
            self.sharingIndicatorView.stopAnimating()
            self.navigationItem.rightBarButtonItem = self.sendButton
        }
    }

    func updateToolbarForCurrentItem() {
        if let item = self.getCurrentShareItem() {
            UIView.transition(with: self.itemToolbar, duration: 0.3, options: .transitionCrossDissolve) {
                self.cropItemButton.isEnabled = item.isImage
                self.previewItemButton.isEnabled = QLPreviewController.canPreview(item.fileURL as QLPreviewItem)
                self.addItemButton.isEnabled = self.shareItemController.shareItems.count < 5
            }
        } else {
            self.cropItemButton.isEnabled = false
            self.previewItemButton.isEnabled = false
        }

        self.removeItemButton.isEnabled = self.shareItemController.shareItems.count > 1
        self.removeItemButton.tintColor = self.shareItemController.shareItems.count > 1 ? nil : .clear
    }

    // MARK: - UIImagePickerController Delegate

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        self.saveImagePickerSettings(picker)

        guard let mediaType = info[.mediaType] as? String else { return }

        if mediaType == "public.image" {
            if let image = info[.originalImage] as? UIImage {
                self.dismiss(animated: true) {
                    self.shareItemController.addItem(with: image)
                    self.collectionViewScrollToEnd()
                }
            }
        } else if mediaType == "public.movie" {
            if let videoUrl = info[.mediaURL] as? URL {
                self.dismiss(animated: true) {
                    self.shareItemController.addItem(with: videoUrl)
                    self.collectionViewScrollToEnd()
                }
            }
        }

    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.saveImagePickerSettings(picker)
        self.dismiss(animated: true)
    }

    func saveImagePickerSettings(_ picker: UIImagePickerController) {
        if picker.sourceType == .camera && picker.cameraCaptureMode == .photo {
            NCUserDefaults.setPreferredCameraFlashMode(picker.cameraFlashMode.rawValue)
        }
    }

    // MARK: - UIDocumentPickerViewController Delegate

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for documentURL in urls {
            self.shareItemController.addItem(with: documentURL)
        }

        self.collectionViewScrollToEnd()
    }

    // MARK: - ScrollView/CollectionView

    public override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: kShareConfirmationCellIdentifier, for: indexPath) as? ShareConfirmationCollectionViewCell
        else { return UICollectionViewCell() }

        let item = self.shareItemController.shareItems[indexPath.row]

        // Setting placeholder here in case we can't generate any other preview
        cell.setPlaceHolderImage(item.placeholderImage)
        cell.setPlaceHolderText(item.fileName)

        if let fileURL = item.fileURL, NCUtils.isImage(fileExtension: fileURL.pathExtension),
           let image = self.shareItemController.getImageFrom(item) {
            // We're able to get an image directly from the fileURL -> use it
            cell.setPreviewImage(image)
        } else {
            self.generatePreview(for: cell, with: collectionView, with: item)
        }

        return cell
    }

    func generatePreview(for cell: ShareConfirmationCollectionViewCell, with collectionView: UICollectionView, with item: ShareItem) {
        let size = CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
        let scale = self.view.window?.screen.scale ?? UIScreen.main.scale

        // updateHandler might be called multiple times, starting from low quality representation to high-quality
        let request = QLThumbnailGenerator.Request(fileAt: item.fileURL, size: size, scale: scale, representationTypes: [.lowQualityThumbnail, .thumbnail])
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { thumbnail, _, error in
            guard error == nil, let thumbnail else { return }

            DispatchQueue.main.async {
                cell.setPreviewImage(thumbnail.uiImage)
            }
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.shareItemController.shareItems.count
    }

    public override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.bounds.width, height: collectionView.bounds.height)
    }

    public override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if self.textView.isFirstResponder {
            self.textView.resignFirstResponder()
        } else {
            self.previewCurrentItem()
        }
    }

    public override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.updatePageControlPage()
    }

    public override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        self.updatePageControlPage()
    }

    func collectionViewScrollToEnd() {
        if let item = self.shareItemController.shareItems.last {
            self.scroll(to: item, animated: true)
        }
    }

    func scroll(to item: ShareItem, animated: Bool) {
        DispatchQueue.main.async {
            if let indexForItem = self.shareItemController.shareItems.firstIndex(of: item) {
                let indexPath = IndexPath(row: indexForItem, section: 0)

                self.shareCollectionView.scrollToItem(at: indexPath, at: [], animated: animated)
            }
        }
    }

    func getCurrentShareItem() -> ShareItem? {
        let currentIndex = Int(self.shareCollectionView.contentOffset.x / self.shareCollectionView.frame.size.width)

        if currentIndex >= self.shareItemController.shareItems.count {
            return nil
        }

        return self.shareItemController.shareItems[currentIndex]
    }

    // MARK: - PageControl

    func pageControlValueChanged() {
        let indexPath = IndexPath(row: self.pageControl.currentPage, section: 0)
        self.shareCollectionView.scrollToItem(at: indexPath, at: [], animated: true)
    }

    func updatePageControlPage() {
        // see: https://stackoverflow.com/a/46181277/2512312
        DispatchQueue.main.async {
            self.pageControl.currentPage = Int(self.shareCollectionView.contentOffset.x / self.shareCollectionView.frame.width)
            self.updateToolbarForCurrentItem()
        }
    }

    // MARK: - PreviewController

    func previewCurrentItem() {
        self.textView.resignFirstResponder()
        guard let item = self.getCurrentShareItem(),
              let fileURL = item.fileURL,
              QLPreviewController.canPreview(fileURL as QLPreviewItem)
        else { return }

        let preview = QLPreviewController()
        preview.dataSource = self
        preview.delegate = self

        NCAppBranding.styleViewController(preview)
        NCAppBranding.styleViewController(self)

        self.navigationController?.pushViewController(preview, animated: true)
    }

    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        // Don't use index here, as this relates to numberOfPreviewItems
        // When we have numberOfPreviewItems > 1 this will show an additional list of items
        guard let item = self.getCurrentShareItem(),
              let fileURL = item.fileURL
        else { return URL(fileURLWithPath: "") as QLPreviewItem }

        return fileURL as QLPreviewItem
    }

    public func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        return .createCopy
    }

    public func previewController(_ controller: QLPreviewController, didSaveEditedCopyOf previewItem: QLPreviewItem, at modifiedContentsURL: URL) {
        if let item = self.getCurrentShareItem() {
            self.shareItemController.update(item, with: modifiedContentsURL)
        }
    }

    // MARK: - ShareItemController Delegate

    public func shareItemControllerItemsChanged(_ shareItemController: ShareItemController) {
        DispatchQueue.main.async {
            if shareItemController.shareItems.isEmpty {
                if let extensionContext = self.extensionContext {
                    let error = NSError(domain: NSCocoaErrorDomain, code: 0)
                    extensionContext.cancelRequest(withError: error)
                } else {
                    self.dismiss(animated: true)
                }
            } else {
                self.shareCollectionView.reloadData()

                // Make sure all changes are fully populated before we update our UI elements
                self.shareCollectionView.layoutIfNeeded()
                self.updateToolbarForCurrentItem()
                self.pageControl.numberOfPages = shareItemController.shareItems.count

                // Update the text input to check if sending is (not-)possible
                self.textDidUpdate(false)
            }
        }
    }

    // MARK: - TOCropViewController Delegate

    public func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
        if let item = self.getCurrentShareItem() {
            self.shareItemController.update(item, with: image)

            // Fixes bug on iPad where collectionView is scrolled between two pages
            self.scroll(to: item, animated: true)
        }

        // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
        cropViewController.transitioningDelegate = nil
        cropViewController.dismiss(animated: true)
    }

    public func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
        if let item = self.getCurrentShareItem() {
            self.scroll(to: item, animated: true)
        }

        // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
        cropViewController.transitioningDelegate = nil
        cropViewController.dismiss(animated: true)
    }

    // MARK: - NKCommon Delegate

    public func authenticationChallenge(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // The pinning check
        if CCCertificate.sharedManager().checkTrustedChallenge(challenge) {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

}
