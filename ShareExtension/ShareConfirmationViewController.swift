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

private let kShareConfirmationOptionsViewHeight: CGFloat = 44

/// How many items can be in a share when more are added from this screen, and how many can be picked at once
/// in the chat. Matches the Android app.
let kShareConfirmationMaxItems = 10

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
    private var shareContentView = MediaPreviewPassthroughView()
    private var shareSilently = false

    /// Quality the images are uploaded in. Deliberately not remembered between shares, so an
    /// exception stays an exception.
    private var imageQuality: ChatImageQuality = .standard

    /// Whether the other participants may modify the shared files.
    private var allowUpdate = false

    /// Where the compressed copies of the running send are, to be thrown away when it is over.
    private var compressedImagesDirectory: URL?

    private var imagePicker: UIImagePickerController?
    private var hud: MBProgressHUD?
    private var objectShareMessage: NCChatMessage?

    /// Whether the media preview is shown, which it is as long as files are shared. Text and rich objects
    /// have their own look.
    private var showsMediaPreview = true {
        didSet {
            self.shareCollectionView.isHidden = !self.showsMediaPreview
            self.toolsView.isHidden = !self.showsMediaPreview
            self.counterView.isHidden = true

            // The media is shown on a dark background, no matter the theme
            self.overrideUserInterfaceStyle = self.showsMediaPreview ? .dark : .unspecified
        }
    }

    private enum ShareConfirmationType {
        case text
        case item
        case objectShare
    }

    // MARK: - UI Controls

    private lazy var sendButton: UIBarButtonItem = {
        let sendButton = UIBarButtonItem(title: NSLocalizedString("Send", comment: "Button to send the shared content to a conversation"), style: .done, target: self, action: #selector(sendButtonPressed))
        sendButton.accessibilityHint = NSLocalizedString("Double tap to share with selected conversations", comment: "")
        return sendButton
    }()

    private lazy var sharingIndicatorView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView()

        if #unavailable(iOS 26.0) {
            indicator.color = NCAppBranding.themeTextColor()
        }

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

    private lazy var toolsView: MediaPreviewToolsView = {
        return MediaPreviewToolsView(buttons: [self.addItemButton, self.cropItemButton, self.markupItemButton, self.removeItemButton])
    }()

    private lazy var counterView = MediaPreviewCounterView()

    private lazy var removeItemButton: UIButton = {
        let button = MediaPreviewToolsView.toolButton(systemName: "trash", accessibilityLabel: NSLocalizedString("Remove", comment: ""))
        button.addTarget(self, action: #selector(removeItemButtonPressed), for: .touchUpInside)

        return button
    }()

    private lazy var cropItemButton: UIButton = {
        let button = MediaPreviewToolsView.toolButton(systemName: "crop.rotate", accessibilityLabel: NSLocalizedString("Crop and rotate", comment: ""))
        button.addTarget(self, action: #selector(cropItemButtonPressed), for: .touchUpInside)

        return button
    }()

    /// Draws on images and previews everything else, both through the QuickLook preview. The look is
    /// adjusted to the shown item in `updateToolsForCurrentItem`.
    private lazy var markupItemButton: UIButton = {
        let button = MediaPreviewToolsView.toolButton(systemName: "pencil.tip.crop.circle", accessibilityLabel: NSLocalizedString("Draw", comment: ""))
        button.addTarget(self, action: #selector(markupItemButtonPressed), for: .touchUpInside)

        return button
    }()

    private lazy var addItemButton: UIButton = {
        let button = MediaPreviewToolsView.toolButton(systemName: "plus", accessibilityLabel: NSLocalizedString("Add more", comment: "Add more photos, videos or files to the share"))

        var items: [UIAction] = []

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
        if InAppCameraViewController.isCameraAvailable {
            items.append(UIAction(title: NSLocalizedString("Camera", comment: ""), image: UIImage(systemName: "camera")) { [unowned self] _ in
                self.textView.resignFirstResponder()
                self.checkAndPresentCamera()
            })
        }
#endif

        items.append(photoLibraryAction)
        items.append(filesAction)

        button.menu = UIMenu(children: items)
        button.showsMenuAsPrimaryAction = true

        return button
    }()

    /// One of the two choices an option button offers.
    private struct UploadOption {
        let title: String
        let subtitle: String
        let image: UIImage?
    }

    // SF Symbols has no SD and HD badges, so they are drawn to match the title next to them
    private lazy var standardQualityOption = UploadOption(
        title: NSLocalizedString("Standard quality", comment: "Upload images at a reduced size"),
        subtitle: NSLocalizedString("Slightly reduced quality, uses less data", comment: ""),
        image: UIImage.badge(withText: "SD", matching: UIFont.preferredFont(forTextStyle: .footnote)))

    private lazy var originalQualityOption = UploadOption(
        title: NSLocalizedString("Original quality", comment: "Upload images unchanged"),
        subtitle: NSLocalizedString("Original resolution and quality are preserved", comment: ""),
        image: UIImage.badge(withText: "HD", matching: UIFont.preferredFont(forTextStyle: .footnote)))

    private lazy var viewOnlyOption = UploadOption(
        title: NSLocalizedString("View-only", comment: "Other participants can only view the shared files"),
        subtitle: NSLocalizedString("Others can only view the files", comment: ""),
        image: UIImage(systemName: "pencil.slash"))

    private lazy var editableOption = UploadOption(
        title: NSLocalizedString("Editable", comment: "Other participants can modify the shared files"),
        subtitle: NSLocalizedString("Others can edit the files", comment: ""),
        image: UIImage(systemName: "pencil"))

    private lazy var imageQualityButton: UIButton = {
        let button = self.optionButton()
        button.accessibilityHint = NSLocalizedString("Double tap to change the quality the images are sent in", comment: "")

        return button
    }()

    private lazy var sharePermissionButton: UIButton = {
        let button = self.optionButton()
        button.accessibilityHint = NSLocalizedString("Double tap to change who can modify the shared files", comment: "")

        return button
    }()

    /// Puts the chosen option on its button and marks it in the menu of it.
    ///
    /// Both are filled in from the same choice on purpose: letting the button show the selection of
    /// its menu by itself would leave what the button says and what is uploaded free to drift apart.
    private func updateOptionButtons() {
        let isStandardQuality = self.imageQuality == .standard
        let quality = isStandardQuality ? self.standardQualityOption : self.originalQualityOption
        self.apply(quality, isDefault: isStandardQuality, to: self.imageQualityButton)
        self.imageQualityButton.menu = UIMenu(title: NSLocalizedString("Image quality", comment: ""),
                                              options: .singleSelection,
                                              children: [
                                                self.action(for: self.standardQualityOption, isChosen: self.imageQuality == .standard) { self.imageQuality = .standard },
                                                self.action(for: self.originalQualityOption, isChosen: self.imageQuality == .original) { self.imageQuality = .original }
                                              ])

        let permission = self.allowUpdate ? self.editableOption : self.viewOnlyOption
        self.apply(permission, isDefault: !self.allowUpdate, to: self.sharePermissionButton)
        self.sharePermissionButton.menu = UIMenu(title: NSLocalizedString("File permissions", comment: ""),
                                                 options: .singleSelection,
                                                 children: [
                                                    self.action(for: self.viewOnlyOption, isChosen: !self.allowUpdate) { self.allowUpdate = false },
                                                    self.action(for: self.editableOption, isChosen: self.allowUpdate) { self.allowUpdate = true }
                                                 ])
    }

    private func apply(_ option: UploadOption, isDefault: Bool, to button: UIButton) {
        button.configuration = self.optionConfiguration(for: option, isDefault: isDefault)
    }

    private func action(for option: UploadOption, isChosen: Bool, choose: @escaping () -> Void) -> UIAction {
        return UIAction(title: option.title,
                        subtitle: option.subtitle,
                        image: option.image,
                        state: isChosen ? .on : .off) { [unowned self] _ in
            choose()
            self.updateOptionButtons()
        }
    }

    private lazy var optionsView: UIStackView = {
        // Takes the space the buttons do not need, so they stay next to each other on the leading
        // side. The lowest priorities make it the first thing to give way, otherwise the buttons
        // would be the ones to shrink and truncate their titles.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let stackView = UIStackView(arrangedSubviews: [self.sharePermissionButton, self.imageQualityButton, spacer])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8

        return stackView
    }()

    private lazy var optionsViewHeightConstraint: NSLayoutConstraint = {
        return self.optionsView.heightAnchor.constraint(equalToConstant: kShareConfirmationOptionsViewHeight)
    }()

    /// A button that shows the option it currently has selected and offers the alternatives in a menu.
    private func optionButton() -> UIButton {
        let button = UIButton(configuration: UIButton.Configuration.gray())
        button.showsMenuAsPrimaryAction = true

        return button
    }

    /// The look of an option button: gray as long as it holds the option a share starts with, and
    /// filled with the theme color once it does not.
    ///
    /// The same pair of colors the unread counter and the selected conversation filters use. The
    /// server picks the text color to be readable on its theme color, which a tinted background of
    /// the same color could not promise.
    private func optionConfiguration(for option: UploadOption, isDefault: Bool) -> UIButton.Configuration {
        var configuration = isDefault ? UIButton.Configuration.gray() : UIButton.Configuration.filled()

        if !isDefault {
            configuration.baseBackgroundColor = NCAppBranding.themeColor()
            configuration.baseForegroundColor = NCAppBranding.themeTextColor()
        }

        configuration.title = option.title
        configuration.image = option.image
        configuration.imagePadding = 4
        // The arrows that tell the button apart from a label, which the button would only show by
        // itself if it let its menu handle the selection
        configuration.indicator = .popup
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .small
        configuration.titleLineBreakMode = .byTruncatingTail
        // The default symbol scale is chunky next to a footnote sized title
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .preferredFont(forTextStyle: .footnote)

            return outgoing
        }

        return configuration
    }

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
        // The preview is dark no matter the theme, so the media stands out the same way in both
        collectionView.backgroundColor = .black
        // The collection view fills the screen: the page is the width of the view, not of its safe area
        collectionView.contentInsetAdjustmentBehavior = .never
        return collectionView
    }()

    private lazy var shareTextView: UITextView = {
        let textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isHidden = true
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        return textView
    }()

    // MARK: - Init.

    public init?(room: NCRoom, thread: NCThread?, account: TalkAccount, serverCapabilities: ServerCapabilities) {
        self.serverCapabilities = serverCapabilities

        super.init(forRoom: room, withAccount: account, withView: self.shareContentView)
        self.thread = thread

        // The media fills the whole screen and sits below the content view. The content view only holds the
        // controls on top of the media, so the media neither shrinks nor jumps when the keyboard shows up.
        self.view.insertSubview(self.shareCollectionView, belowSubview: self.shareContentView)

        self.shareContentView.addSubview(self.shareTextView)
        self.shareContentView.addSubview(self.counterView)
        self.shareContentView.addSubview(self.toolsView)
        self.shareContentView.addSubview(self.optionsView)

        NSLayoutConstraint.activate([
            self.shareTextView.leftAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leftAnchor, constant: 20),
            self.shareTextView.rightAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.rightAnchor, constant: -20),
            self.shareTextView.bottomAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])

        NSLayoutConstraint.activate([
            self.shareCollectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.shareCollectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.shareCollectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),

            self.counterView.centerXAnchor.constraint(equalTo: self.shareContentView.centerXAnchor),

            self.toolsView.leadingAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            self.toolsView.bottomAnchor.constraint(equalTo: self.optionsView.topAnchor, constant: -8),
            self.toolsView.heightAnchor.constraint(equalToConstant: 44)
        ])

        if #unavailable(iOS 26) {
            self.shareContentView.addSubview(self.toLabelView)

            NSLayoutConstraint.activate([
                self.toLabelView.leftAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leftAnchor),
                self.toLabelView.rightAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.rightAnchor),
                self.toLabelView.topAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.topAnchor),
                self.toLabelView.heightAnchor.constraint(equalToConstant: 36),

                self.shareTextView.topAnchor.constraint(equalTo: self.toLabelView.bottomAnchor, constant: 20),

                self.shareCollectionView.topAnchor.constraint(equalTo: self.toLabelView.bottomAnchor),
                self.counterView.topAnchor.constraint(equalTo: self.toLabelView.bottomAnchor, constant: 8)
            ])
        } else {
            // On iOS 26 we don't have a toLabel anymore, so we need to constraint to the safe area as well.
            // The navigation bar is glass there, the media can go below it.
            NSLayoutConstraint.activate([
                self.shareTextView.topAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.topAnchor),

                self.shareCollectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
                self.counterView.topAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.topAnchor, constant: 8)
            ])
        }

        NSLayoutConstraint.activate([
            self.optionsView.leftAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.leftAnchor, constant: 20),
            self.optionsView.rightAnchor.constraint(equalTo: self.shareContentView.safeAreaLayoutGuide.rightAnchor, constant: -20),
            self.optionsView.bottomAnchor.constraint(equalTo: self.textInputbar.topAnchor),
            self.optionsViewHeightConstraint
        ])
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func shareText(_ sharedText: String) {
        self.shareType = .text

        DispatchQueue.main.async {
            self.setTextInputbarHidden(true, animated: false)
            self.showsMediaPreview = false
            self.shareTextView.isHidden = false
            self.shareTextView.text = sharedText
            self.updateOptionsView()

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
            self.showsMediaPreview = false
            self.shareTextView.isHidden = false
            self.shareTextView.isUserInteractionEnabled = false
            self.shareTextView.text = objectShareMessage.parsedMessage().string
            self.objectShareMessage = objectShareMessage
            self.updateOptionsView()
        }
    }

    // MARK: - View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Thumbnails are generated at the display scale, so they have to be regenerated when it changes.
        // Registered before the token guard below, which can return early.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitDisplayScale.self]) { (self: ShareConfirmationViewController, _) in
                self.shareCollectionView.reloadData()
            }
        }

        // Set up before the token guard below, which can return early: without the cell registered,
        // the first reload of the collection view raises
        let bundle = Bundle(for: ShareConfirmationCollectionViewCell.self)
        self.shareCollectionView.register(UINib(nibName: kShareConfirmationTableCellNibName, bundle: bundle), forCellWithReuseIdentifier: kShareConfirmationCellIdentifier)
        self.shareCollectionView.delegate = self

        self.overrideUserInterfaceStyle = .dark
        self.configureCaptionInputbar()

        // Configure communication lib
        guard let userToken = NCKeyChainController.sharedInstance().token(forAccountId: self.account.accountId) else { return }
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

    }

    /// Makes the inputbar the caption field on top of the media: no bar of its own, a dark field and a round send button.
    private func configureCaptionInputbar() {
        self.textInputbar.backgroundColor = .clear

        self.textView.keyboardAppearance = .dark
        self.textView.textColor = .white
        self.textView.placeholder = NSLocalizedString("Add a caption …", comment: "Placeholder of the field for the text sent along with the photos and files")
        self.textView.placeholderColor = UIColor.white.withAlphaComponent(0.6)

        if #unavailable(iOS 26.0) {
            self.textView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            self.textView.layer.borderWidth = 0

            self.rightButton.backgroundColor = NCAppBranding.themeColor()
            self.rightButton.tintColor = NCAppBranding.themeTextColor()
            self.rightButton.clipsToBounds = true
        }
    }

    /// The options that apply to what is being shared right now.
    ///
    /// Only uploaded files have a quality and a permission to choose, and each of both options
    /// needs something to apply to.
    internal var availableOptions: (imageQuality: Bool, sharePermission: Bool) {
        guard self.shareType == .item else { return (false, false) }

        let hasCompressibleImage = self.shareItemController.shareItems.contains { ChatImageCompressor.supportsCompression(fileName: $0.fileName) }

        // Update permissions are only supported by the conversation subfolders of the server
        return (hasCompressibleImage, self.room.supportsConversationSubfolders)
    }

    /// Shows the options that apply to what is being shared right now, and hides the row when none do.
    private func updateOptionsView() {
        self.updateOptionButtons()

        let options = self.availableOptions

        self.imageQualityButton.isHidden = !options.imageQuality
        self.sharePermissionButton.isHidden = !options.sharePermission

        let showOptions = options.imageQuality || options.sharePermission

        self.optionsView.isHidden = !showOptions
        self.optionsViewHeightConstraint.constant = showOptions ? kShareConfirmationOptionsViewHeight : 0
    }

    /// Whether a caption can be added to what is being shared. When it can, the send button is part
    /// of the input bar, otherwise it sits in the navigation bar.
    private var captionAllowed: Bool {
        guard self.shareType == .item else { return false }

        return NCDatabaseManager.sharedInstance().serverHasTalkCapability(.mediaCaption, forAccountId: self.account.accountId)
    }

    public override func viewWillAppear(_ animated: Bool) {
        // Add the cancel button in viewWillAppear, so that the caller can change the isModal property after initialization
        if self.isModal {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
            cancelButton.accessibilityHint = NSLocalizedString("Double tap to dismiss sharing options", comment: "")

            self.navigationItem.leftBarButtonItem = cancelButton

            if #unavailable(iOS 26) {
                self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
            }
        }

        if !self.captionAllowed {
            self.navigationItem.rightBarButtonItem = self.sendButton
            if #unavailable(iOS 26) {
                self.navigationItem.rightBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
            }
            self.setTextInputbarHidden(true, animated: false)
        } else {
            let silentSendAction = UIAction(title: NSLocalizedString("Send without notification", comment: ""), image: UIImage(systemName: "bell.slash")) { [unowned self] _ in
                self.silentSendPressed()
            }

            self.rightButton.menu = UIMenu(children: [silentSendAction])
        }

        self.updateOptionsView()
        self.configureCaptionInputbar()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if #unavailable(iOS 26.0) {
            self.rightButton.layer.cornerRadius = self.rightButton.bounds.height / 2
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

    func markupItemButtonPressed() {
        // The QuickLook preview offers the markup of images, see previewController(_:editingModeFor:)
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

#if !APP_EXTENSION
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
            let camera = InAppCameraViewController()
            camera.delegate = self
            camera.modalPresentationStyle = .fullScreen
            self.present(camera, animated: true)
        }
    }
#endif

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
        NCAPIController.sharedInstance().sendChatMessage(self.shareTextView.text, toRoom: self.room.token, threadTitle: nil, replyTo: -1, referenceId: nil, silently: false, forAccount: self.account) { error in
            if let error {
                NCLog.log(String(format: "Failed to share text. Error: %@", error.localizedDescription))
                self.delegate?.shareConfirmationViewControllerDidFail(self)
            } else {
                NCIntentController.sharedInstance().donateSendMessageIntent(for: self.room)
                self.delegate?.shareConfirmationViewControllerDidFinish(self)
            }

            self.stopAnimatingSharingIndicator()
        }
    }

    func sendObjectShare() {
        guard let richObjectFromObjectShare = objectShareMessage?.richObjectFromObjectShare else { return }

        NCAPIController.sharedInstance().shareRichObject(richObjectFromObjectShare, inRoom: self.room.token, forAccount: self.account) { error in
            if let error {
                NCLog.log(String(format: "Failed to share rich object. Error: %@", error.localizedDescription))
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
        // Compressing the images happens before there is any progress to report
        self.hud?.mode = .indeterminate
        self.hud?.label.text = String.localizedStringWithFormat(NSLocalizedString("Uploading %ld elements", comment: ""), self.shareItemController.shareItems.count)

        // Add caption to last shareItem
        if let shareItem = self.shareItemController.shareItems.last {
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(.mediaCaption, forAccountId: self.account.accountId) {
                let messageParameters = self.mentionsDict.asJSONString() ?? ""
                let message = NCChatMessage()
                message.message = self.replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: self.textView.text, parameters: messageParameters)
                message.messageParametersJSONString = messageParameters

                shareItem.caption = message.sendingMessage
            }
        }

        let shareItems = self.shareItemController.shareItems

        Task {
            defer { bgTask.stopBackgroundTask() }

            let uploads = await self.uploads(for: shareItems, quality: self.imageQuality)

            self.hud?.mode = .annularDeterminate

            let results: [Result<Void, Error>]

            do {
                results = try await ChatFileUploader.upload(uploads) { index, fractionCompleted in
                    shareItems[index].uploadProgress = fractionCompleted
                    self.updateHudProgress()
                }
            } catch {
                // Without a draft folder nothing was uploaded at all
                NCLog.log("Could not prepare the upload folder. Error: \(error.localizedDescription)")
                self.finishUploads(withErrors: [NSLocalizedString("Could not prepare upload folder", comment: "")], succeededItems: [])
                return
            }

            var errors: [String] = []
            var succeededItems: [ShareItem] = []

            for (shareItem, result) in zip(shareItems, results) {
                switch result {
                case .success:
                    succeededItems.append(shareItem)
                case .failure(let error):
                    NCLog.log("Failed to upload \(shareItem.fileName ?? "file"). Error: \(error.localizedDescription)")
                    errors.append(self.message(for: error))
                }
            }

            self.finishUploads(withErrors: errors, succeededItems: succeededItems)
        }
    }

    /// Builds the uploads for the items to share, compressing the images among them when the
    /// standard quality is asked for.
    internal func uploads(for shareItems: [ShareItem], quality: ChatImageQuality) async -> [ChatFileUpload] {
        guard quality == .standard,
              let directory = ChatImageCompressor.temporaryDirectory()
        else {
            NCLog.log("Sharing \(shareItems.count) files in their original quality")

            return shareItems.map { self.upload(for: $0) }
        }

        // Only the plain values are handed to the compression, so it does not touch the share items
        var images: [Int: (url: URL, fileName: String)] = [:]

        for (index, shareItem) in shareItems.enumerated() {
            guard let fileURL = shareItem.fileURL,
                  ChatImageCompressor.supportsCompression(fileName: shareItem.fileName)
            else { continue }

            images[index] = (fileURL, shareItem.fileName)
        }

        // Re-encoding the images should not block the main thread
        let compressedImages = await Task.detached {
            var compressedImages: [Int: (url: URL, fileName: String)] = [:]

            for (index, image) in images {
                if let compressed = ChatImageCompressor.compressedCopy(of: image.url, named: image.fileName, in: directory) {
                    compressedImages[index] = compressed
                }
            }

            return compressedImages
        }.value

        NCLog.log("Sharing \(shareItems.count) files, compressed \(compressedImages.count) of the \(images.count) images among them")

        self.compressedImagesDirectory = directory

        return shareItems.enumerated().map { index, shareItem in
            self.upload(for: shareItem, compressedTo: compressedImages[index])
        }
    }

    private func upload(for shareItem: ShareItem, compressedTo compressedImage: (url: URL, fileName: String)? = nil) -> ChatFileUpload {
        var metaData = ChatFileUploadMetadata()
        metaData.caption = shareItem.caption
        metaData.silent = self.shareSilently
        metaData.threadId = self.thread?.threadId

        var upload = ChatFileUpload(localPath: compressedImage?.url.path ?? shareItem.filePath,
                                    fileName: compressedImage?.fileName ?? shareItem.fileName,
                                    room: self.room,
                                    account: self.account)
        upload.metadata = metaData
        upload.allowUpdate = self.allowUpdate

        return upload
    }

    private func finishUploads(withErrors errors: [String], succeededItems: [ShareItem]) {
        self.stopAnimatingSharingIndicator()
        self.hud?.hide(animated: true)

        if let directory = self.compressedImagesDirectory {
            ChatImageCompressor.removeTemporaryDirectory(directory)
            self.compressedImagesDirectory = nil
        }

        guard !errors.isEmpty else {
            self.shareItemController.removeAllItems()
            self.delegate?.shareConfirmationViewControllerDidFinish(self)
            return
        }

        // We remove the successfully uploaded items, so only the failed ones are kept
        self.shareItemController.remove(succeededItems)

        let alert = UIAlertController(title: NSLocalizedString("Upload failed", comment: ""),
                                      message: errors.joined(separator: "\n"),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))

        self.present(alert, animated: true)
    }

    private func message(for error: Error) -> String {
        switch error {
        case ChatFileUploadError.destinationUnavailable:
            return NSLocalizedString("Could not prepare upload folder", comment: "")
        case ChatFileUploadError.attachmentFolderUnavailable:
            return NSLocalizedString("Failed to check or create attachment folder", comment: "")
        case ChatFileUploadError.quotaExceeded:
            return NSLocalizedString("User storage quota exceeded", comment: "")
        case ChatFileUploadError.tooManyRequests:
            return NSLocalizedString("Too many requests, please try again later", comment: "")
        case ChatFileUploadError.uploadFailed(_, let errorDescription):
            return errorDescription
        default:
            return error.localizedDescription
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
            // With a caption there is no send button in the navigation bar, it lives in the input bar
            self.navigationItem.rightBarButtonItem = self.captionAllowed ? nil : self.sendButton
        }
    }

    func updateToolsForCurrentItem() {
        guard self.shareType == .item else { return }

        let itemCount = self.shareItemController.shareItems.count

        if itemCount > 0 {
            self.counterView.update(current: self.currentPageIndex + 1, total: itemCount)
        }

        UIView.transition(with: self.toolsView, duration: 0.3, options: .transitionCrossDissolve) {
            self.addItemButton.isEnabled = itemCount < kShareConfirmationMaxItems
            self.removeItemButton.isHidden = itemCount <= 1

            if let item = self.getCurrentShareItem() {
                self.cropItemButton.isEnabled = item.isImage
                self.markupItemButton.isEnabled = QLPreviewController.canPreview(item.fileURL as QLPreviewItem)

                // Images can be drawn on in the preview, everything else can only be looked at
                self.markupItemButton.setImage(UIImage(systemName: item.isImage ? "pencil.tip.crop.circle" : "eye"), for: .normal)
                self.markupItemButton.accessibilityLabel = item.isImage ? NSLocalizedString("Draw", comment: "") : NSLocalizedString("Preview", comment: "")
            } else {
                self.cropItemButton.isEnabled = false
                self.markupItemButton.isEnabled = false
            }
        }
    }

    // MARK: - UIImagePickerController Delegate

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
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
        self.dismiss(animated: true)
    }

    // MARK: - UIDocumentPickerViewController Delegate

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let freeSlots = max(0, kShareConfirmationMaxItems - self.shareItemController.shareItems.count)

        for documentURL in urls.prefix(freeSlots) {
            self.shareItemController.addItem(with: documentURL)
        }

        self.collectionViewScrollToEnd()

        if urls.count > freeSlots {
            let message = String.localizedStringWithFormat(NSLocalizedString("You can select up to %ld items", comment: "Shown when more photos and videos are selected than can be sent at once"), kShareConfirmationMaxItems)
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))

            DispatchQueue.main.async {
                self.present(alert, animated: true)
            }
        }
    }

    // MARK: - ScrollView/CollectionView

    public override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: kShareConfirmationCellIdentifier, for: indexPath) as? ShareConfirmationCollectionViewCell
        else { return UICollectionViewCell() }

        // removeAllItems() after a send does not reload, so prefetching during the dismissal can still ask for old rows
        let shareItems = self.shareItemController.shareItems
        guard indexPath.row < shareItems.count else { return cell }

        let item = shareItems[indexPath.row]

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
        let scale = self.traitCollection.displayScale

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
        self.updateCurrentPage()
    }

    public override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        self.updateCurrentPage()
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

    /// The index of the page that is shown, kept inside the items. A removal can leave the offset behind the last one.
    private var currentPageIndex: Int {
        let width = self.shareCollectionView.frame.size.width
        let itemCount = self.shareItemController.shareItems.count

        guard width > 0, itemCount > 0 else { return 0 }

        // see: https://stackoverflow.com/a/46181277/2512312
        return max(0, min(Int((self.shareCollectionView.contentOffset.x / width).rounded()), itemCount - 1))
    }

    func getCurrentShareItem() -> ShareItem? {
        let shareItems = self.shareItemController.shareItems

        if shareItems.isEmpty {
            return nil
        }

        return shareItems[self.currentPageIndex]
    }

    func updateCurrentPage() {
        DispatchQueue.main.async {
            self.updateToolsForCurrentItem()
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
                self.updateToolsForCurrentItem()
                self.updateOptionsView()

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

#if !APP_EXTENSION
// MARK: - InAppCameraViewController Delegate

extension ShareConfirmationViewController: InAppCameraViewControllerDelegate {

    // The camera does not close itself, that is up to us. The shot becomes one more item of the share and
    // the screen stays open, showing it.
    func inAppCameraViewController(_ controller: InAppCameraViewController, didCaptureMediaAt fileURL: URL) {
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }

            self.shareItemController.addItem(with: fileURL)
            self.collectionViewScrollToEnd()
        }
    }

    func inAppCameraViewControllerDidCancel(_ controller: InAppCameraViewController) {
        controller.dismiss(animated: true)
    }
}
#endif
