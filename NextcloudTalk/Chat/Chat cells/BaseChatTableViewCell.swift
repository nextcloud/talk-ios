//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import MapKit
import SwiftyGif
import SDWebImage

protocol BaseChatTableViewCellDelegate: AnyObject {

    func cellWantsToScroll(to message: NCChatMessage)
    func cellWantsToReply(to message: NCChatMessage)
    func cellDidSelectedReaction(_ reaction: NCChatReaction!, for message: NCChatMessage)

    func cellWants(toDownloadFile fileParameter: NCMessageFileParameter, for message: NCChatMessage)
    func cellHasDownloadedImagePreview(withSize size: CGSize, for message: NCChatMessage)

    func cellWants(toOpenLocation geoLocationRichObject: GeoLocationRichObject)

    func cellWants(toPlayAudioFile message: NCChatMessage)
    func cellWants(toPauseAudioFile fileParameter: NCMessageFileParameter)
    func cellWants(toChangeProgress progress: CGFloat, fromAudioFile fileParameter: NCMessageFileParameter)

    func cellWants(toOpenPoll poll: NCMessageParameter)

    func cellWants(toShowThread message: NCChatMessage)
}

// Common elements
public let chatMessageCellPreviewCornerRadius = 4.0

// Message cell
public let chatMessageCellIdentifier = "chatMessageCellIdentifier"
public let chatGroupedMessageCellIdentifier = "chatGroupedMessageCellIdentifier"
public let chatReplyMessageCellIdentifier = "chatReplyMessageCellIdentifier"
public let chatMessageCellMinimumHeight = 45.0
public let chatGroupedMessageCellMinimumHeight = 25.0

// File cell
public let fileMessageCellIdentifier = "fileMessageCellIdentifier"
public let fileGroupedMessageCellIdentifier = "fileGroupedMessageCellIdentifier"
public let fileMessageCellMinimumHeight = 50.0
public let fileMessageCellFileMaxPreviewHeight = 120.0
public let fileMessageCellFileMaxPreviewWidth = 230.0
public let fileMessageCellMediaFilePreviewHeight = 230.0
public let fileMessageCellMediaFileMaxPreviewWidth = 230.0
public let fileMessageCellVideoPlayIconSize = 48.0

// Location cell
public let locationMessageCellIdentifier = "locationMessageCellIdentifier"
public let locationGroupedMessageCellIdentifier = "locationGroupedMessageCellIdentifier"
public let locationMessageCellMinimumHeight = 50.0
public let locationMessageCellPreviewHeight = 120.0
public let locationMessageCellPreviewWidth = 240.0

// Voice message cell
public let voiceMessageCellIdentifier = "voiceMessageCellIdentifier"
public let voiceGroupedMessageCellIdentifier = "voiceGroupedMessageCellIdentifier"
public let voiceMessageCellPlayerHeight = 52.0
public let voiceMessageCellPlayerWidth = 450.0

// Poll cell
public let pollMessageCellIdentifier = "pollMessageCellIdentifier"
public let pollGroupedMessageCellIdentifier = "pollGroupedMessageCellIdentifier"

class BaseChatTableViewCell: UITableViewCell, AudioPlayerViewDelegate, ReactionsViewDelegate {

    // TODO: Reset cache when theming changes
    static var bubbleColorCache = NSCache<NSString, UIColor>()

    public weak var delegate: BaseChatTableViewCellDelegate?

    @IBOutlet weak var avatarButton: AvatarButton!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var statusView: UIStackView!
    @IBOutlet weak var messageBodyView: UIView!
    @IBOutlet weak var messageBodyViewTopConstraint: NSLayoutConstraint!

    @IBOutlet weak var reactionStackView: UIStackView!

    @IBOutlet weak var headerPart: UIView!
    @IBOutlet weak var subheaderPart: UIView!
    @IBOutlet weak var quotePart: UIView!
    @IBOutlet weak var referencePart: UIView!
    @IBOutlet weak var reactionPart: UIView!
    @IBOutlet weak var footerPart: UIView!

    @IBOutlet weak var bubbleView: UIView!

    // Since we use different relations depending on the bubble (other user or app user) we setup
    // the constraints programmatically instead of in interface builder
    lazy var bubbleViewLeftConstraintEqual: NSLayoutConstraint = {
        return bubbleView.leadingAnchor.constraint(equalTo: avatarButton.trailingAnchor, constant: 10)
    }()

    lazy var bubbleViewLeftConstraintGreaterThan: NSLayoutConstraint = {
        return bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: avatarButton.trailingAnchor, constant: 40)
    }()

    lazy var bubbleViewRightConstraintEqual: NSLayoutConstraint = {
        return bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10)
    }()

    lazy var bubbleViewRightConstraintLessThan: NSLayoutConstraint = {
        return bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -64)
    }()

    lazy var threadRepliesButton: NCButton = {
        let button = NCButton()
        button.setButtonStyle(style: .tertiary)
        button.tintColor = .label
        button.configuration?.image = UIImage(systemName: "arrowshape.turn.up.left")
        button.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        button.configuration?.imagePadding = 4

        self.reactionStackView.insertArrangedSubview(button, at: 0)

        return button
    }()

    public var message: NCChatMessage?
    public var room: NCRoom?
    public var account: TalkAccount?

    internal var threadTitleLabel: UILabel?
    internal var quotedMessageView: QuotedMessageView?
    internal var reactionView: ReactionsView?
    internal var referenceView: ReferenceView?

    internal var replyGestureRecognizer: DRCellSlideGestureRecognizer?

    // Message cell
    internal var messageTextView: MessageBodyTextView?

    // File cell
    internal var filePreviewImageView: UIImageView?
    internal var filePreviewImageViewHeightConstraint: NSLayoutConstraint?
    internal var filePreviewImageViewWidthConstraint: NSLayoutConstraint?
    internal var fileActivityIndicator: MDCActivityIndicator?
    internal var filePreviewActivityIndicator: MDCActivityIndicator?
    internal var filePreviewPlayIconImageView: UIImageView?
    internal var fileCurrentRequest: SDWebImageCombinedOperation?

    // Location cell
    internal var locationPreviewImageView: UIImageView?
    internal var locationMapSnapshooter: MKMapSnapshotter?
    internal var locationPreviewImageViewHeightConstraint: NSLayoutConstraint?
    internal var locationPreviewImageViewWidthConstraint: NSLayoutConstraint?

    // Audio cell
    internal var audioPlayerView: AudioPlayerView?

    // Poll cell
    internal var pollMessageView: PollMessageView?

    override func awakeFromNib() {
        super.awakeFromNib()

        self.commonInit()
    }

    func commonInit() {
        self.headerPart.isHidden = false
        self.subheaderPart.isHidden = true
        self.quotePart.isHidden = true
        self.referencePart.isHidden = true
        self.reactionPart.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.message = nil
        self.avatarButton.cancelCurrentRequest()
        self.avatarButton.setImage(nil, for: .normal)

        self.quotedMessageView?.avatarImageView.cancelCurrentRequest()
        self.quotedMessageView?.avatarImageView.image = nil

        self.headerPart.isHidden = false
        self.avatarButton.isHidden = false
        self.subheaderPart.isHidden = true
        self.quotePart.isHidden = true
        self.referencePart.isHidden = true
        self.reactionPart.isHidden = true
        self.threadRepliesButton.isHidden = true

        // There might be a better way to do this, but for now we remove the elements so they don't mess
        // with autolayout even when they are hidden
        self.reactionView?.removeFromSuperview()
        self.reactionView = nil

        self.quotedMessageView?.removeFromSuperview()
        self.quotedMessageView = nil

        self.threadTitleLabel?.removeFromSuperview()
        self.threadTitleLabel = nil

        self.messageBodyViewTopConstraint.constant = 5

        self.referenceView?.prepareForReuse()

        self.prepareForReuseFileCell()
        self.prepareForReuseLocationCell()
        self.prepareForReuseAudioCell()

        if let replyGestureRecognizer {
            self.removeGestureRecognizer(replyGestureRecognizer)
            self.replyGestureRecognizer = nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func setup(for message: NCChatMessage, inRoom room: NCRoom, forThread thread: NCThread?, withAccount account: TalkAccount) {
        self.message = message
        self.room = room
        self.account = account

        self.avatarButton.setActorAvatar(forMessage: message, withAccount: account)
        self.avatarButton.menu = self.getDeferredUserMenu()
        self.avatarButton.showsMenuAsPrimaryAction = true

        let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
        self.dateLabel.text = NCUtils.getTime(fromDate: date)

        let messageActor = message.actor
        let titleLabel = messageActor.attributedDisplayName

        if let lastEditActorDisplayName = message.lastEditActorDisplayName, message.lastEditTimestamp > 0 {
            var editedString = ""

            if message.lastEditActorId == message.actorId, message.lastEditActorType == "users" {
                editedString = NSLocalizedString("edited", comment: "A message was edited")
                editedString = " (\(editedString))"
            } else {
                editedString = NSLocalizedString("edited by", comment: "A message was edited by ...")
                editedString = " (\(editedString) \(lastEditActorDisplayName))"
            }

            let editedAttributedString = editedString.withTextColor(.tertiaryLabel)

            titleLabel.append(editedAttributedString)
        }

        self.titleLabel.attributedText = titleLabel

        let shouldShowDeliveryStatus = NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityChatReadStatus, for: room)
        var shouldShowReadStatus = false

        if let roomCapabilities = NCDatabaseManager.sharedInstance().roomTalkCapabilities(for: room) {
            shouldShowReadStatus = !(roomCapabilities.readStatusPrivacy)
        }

        let isOwnMessage = message.isMessage(from: account.userId)

        // This check is just a workaround to fix the issue with the deleted parents returned by the API.
        if let parent = message.parent, message.willShowParentMessageInThread(thread) {
            self.showQuotePart()

            let quoteString = parent.parsedMarkdownForChat()?.string ?? ""
            self.quotedMessageView?.messageLabel.text = quoteString
            self.quotedMessageView?.actorLabel.attributedText = parent.actor.attributedDisplayName
            self.quotedMessageView?.highlighted = parent.isMessage(from: account.userId)
            self.quotedMessageView?.avatarImageView.setActorAvatar(forMessage: parent, withAccount: account)
        }

        if message.isGroupMessage, !message.willShowParentMessageInThread(thread) {
            self.titleLabel.text = ""
            self.headerPart.isHidden = true
            self.avatarButton.isHidden = true
            self.messageBodyViewTopConstraint.constant = 10
        }

        self.bubbleViewLeftConstraintEqual.isActive = !isOwnMessage
        self.bubbleViewLeftConstraintGreaterThan.isActive = isOwnMessage

        self.bubbleViewRightConstraintEqual.isActive = isOwnMessage
        self.bubbleViewRightConstraintLessThan.isActive = !isOwnMessage

        var backgroundColor: UIColor? = .secondarySystemGroupedBackground

        if isOwnMessage {
            backgroundColor = BaseChatTableViewCell.bubbleColorCache.object(forKey: account.accountId as NSString)

            if backgroundColor == nil {
                backgroundColor = NCAppBranding.elementColorBackground()
                BaseChatTableViewCell.bubbleColorCache.setObject(backgroundColor!, forKey: account.accountId as NSString)
            }

            // Ensure titleLabel does not interfere with width calculation (only on devices, not simulator)
            self.titleLabel.text = ""
            self.headerPart.isHidden = true
            self.avatarButton.isHidden = true
            self.messageBodyViewTopConstraint.constant = 10
        }

        self.bubbleView.backgroundColor = backgroundColor

        // Make sure the status view is empty, when no delivery state should be set
        self.statusView.subviews.forEach {
            if $0 != dateLabel {
                $0.removeFromSuperview()
            }
        }

        if message.isDeleting {
            self.setDeliveryState(to: .deleting)
        } else if message.sendingFailed {
            self.setDeliveryState(to: .failed)
        } else if message.isTemporary {
            self.setDeliveryState(to: .sending)
        } else if message.isMessage(from: account.userId), shouldShowDeliveryStatus {
            if room.lastCommonReadMessage >= message.messageId, shouldShowReadStatus {
                self.setDeliveryState(to: .read)
            } else {
                self.setDeliveryState(to: .sent)
            }
        }

        if message.isSilent {
            addSystemImageToStatus("bell.slash")
        }

        if isOwnMessage, message.lastEditTimestamp > 0 {
            addSystemImageToStatus("pencil")
        }

        let reactionsArray = message.reactionsArray()

        if !reactionsArray.isEmpty {
            self.showReactionsPart()
            self.reactionView?.updateReactions(reactions: reactionsArray)
        }

        // Show thread title and replies button for the thread original message (if not in a thread view)
        if thread == nil, message.isThreadOriginalMessage() {
            self.showThreadTitle()
            self.showThreadRepliesButton()
        }

        if message.containsURL() {
            self.showReferencePart()

            message.getReferenceData { message, referenceDataRaw, url in
                guard let cellMessage = self.message,
                      let referenceMessage = message,
                      cellMessage.isSameMessage(referenceMessage)
                else { return }

                if referenceDataRaw == nil, let deckCard = cellMessage.deckCard() {
                    // In case we were unable to retrieve reference data (for example if the user has no permissions)
                    // but the message is a shared deck card, we use the shared information to show the deck view
                    self.referenceView?.update(for: deckCard)
                } else if let referenceData = referenceDataRaw as? [String: [String: AnyObject]], let url {
                    self.referenceView?.update(for: referenceData, and: url)
                }
            }
        }

        if message.isReplyable, !message.isDeleting {
            self.addSlideToReplyGestureRecognizer(for: message)
        }

        if message.isVoiceMessage {
            // Audio message
            self.setupForAudioCell(with: message)
        } else if message.poll != nil {
            // Poll message
            self.setupForPollCell(with: message)
        } else if message.file() != nil {
            // File message
            self.setupForFileCell(with: message, with: account)
        } else if message.geoLocation() != nil {
            // Location message
            self.setupForLocationCell(with: message)
        } else {
            // Normal text message
            self.setupForMessageCell(with: message)
        }

        if message.isDeletedMessage {
            self.statusView.isHidden = true
            self.messageTextView?.textColor = .tertiaryLabel
        } else {
            self.statusView.isHidden = false
        }

        NotificationCenter.default.addObserver(self, selector: #selector(didChangeIsDownloading(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeIsDownloading, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeDownloadProgress(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeDownloadProgress, object: nil)
    }

    func addSystemImageToStatus(_ systemName: String) {
        let view = UIImageView(frame: .init(x: 0, y: 0, width: 20, height: 14))
        let image = UIImage(systemName: systemName)?.withTintColor(.secondaryLabel).withRenderingMode(.alwaysOriginal)

        view.image = NCUtils.renderAspectImage(image: image, ofSize: .init(width: 20, height: 12), centerImage: true)
        view.contentMode = .scaleAspectFit
        view.widthAnchor.constraint(equalToConstant: 20).isActive = true
        view.heightAnchor.constraint(equalToConstant: 14).isActive = true

        self.statusView.addArrangedSubview(view)
    }

    func addSlideToReplyGestureRecognizer(for message: NCChatMessage) {
        if let action = DRCellSlideAction(forFraction: 0.2) {
            action.behavior = .pullBehavior
            action.activeColor = .label
            action.inactiveColor = .placeholderText
            action.activeBackgroundColor = self.backgroundColor
            action.inactiveBackgroundColor = self.backgroundColor
            action.icon = UIImage(systemName: "arrowshape.turn.up.left")

            action.willTriggerBlock = { [unowned self] _, _ -> Void in
                self.delegate?.cellWantsToReply(to: message)
            }

            action.didChangeStateBlock = { _, active -> Void in
                if active {
                    // Actuate `Peek` feedback (weak boom)
                    AudioServicesPlaySystemSound(1519)
                }
            }

            let replyGestureRecognizer = DRCellSlideGestureRecognizer()
            self.replyGestureRecognizer = replyGestureRecognizer

            replyGestureRecognizer.leftActionStartPosition = 80
            replyGestureRecognizer.addActions(action)

            self.addGestureRecognizer(replyGestureRecognizer)
        }
    }

    func setDeliveryState(to deliveryState: ChatMessageDeliveryState) {
        if deliveryState == .sending || deliveryState == .deleting {
            let activityIndicator = MDCActivityIndicator(frame: .init(x: 0, y: 0, width: 20, height: 20))

            activityIndicator.radius = 6.0
            activityIndicator.strokeWidth = 1.5
            activityIndicator.cycleColors = [.secondaryLabel]
            activityIndicator.startAnimating()
            activityIndicator.widthAnchor.constraint(equalToConstant: 20).isActive = true

            self.statusView.addArrangedSubview(activityIndicator)

        } else if deliveryState == .failed {
            let errorView = UIImageView(frame: .init(x: 0, y: 0, width: 20, height: 20))
            let errorImage = UIImage(systemName: "exclamationmark.circle")?.withTintColor(.systemRed).withRenderingMode(.alwaysOriginal)

            errorView.image = errorImage
            errorView.contentMode = .scaleAspectFit
            errorView.widthAnchor.constraint(equalToConstant: 20).isActive = true

            self.statusView.addArrangedSubview(errorView)

        } else if deliveryState == .sent || deliveryState == .read {
            var checkImageName = "check"

            if deliveryState == .read {
                checkImageName = "check-all"
            }

            let checkImage = UIImage(named: checkImageName)?.withRenderingMode(.alwaysTemplate)
            let checkView = UIImageView(frame: .init(x: 0, y: 0, width: 20, height: 20))

            checkView.image = checkImage
            checkView.contentMode = .scaleAspectFit
            checkView.tintColor = .secondaryLabel
            checkView.accessibilityIdentifier = "MessageSent"
            checkView.widthAnchor.constraint(equalToConstant: 20).isActive = true

            self.statusView.addArrangedSubview(checkView)
        }
    }

    // MARK: - SubheaderPart

    func showThreadTitle() {
        self.subheaderPart.isHidden = false

        if self.threadTitleLabel == nil, let threadTitle = message?.threadTitle {
            let threadTitleLabel = UILabel()
            threadTitleLabel.font = .preferredFont(for: .body, weight: .semibold)
            self.threadTitleLabel = threadTitleLabel

            let config = UIImage.SymbolConfiguration(font: threadTitleLabel.font, scale: .small)
            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: "bubble.left.and.bubble.right", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)

            let text = NSMutableAttributedString(attachment: attachment)
            text.append(NSAttributedString(string: " \(threadTitle)"))
            text.addAttribute(.foregroundColor, value: UIColor.label,
                              range: NSRange(location: 0, length: text.length))
            threadTitleLabel.attributedText = text

            threadTitleLabel.translatesAutoresizingMaskIntoConstraints = false

            self.subheaderPart.addSubview(threadTitleLabel)

            NSLayoutConstraint.activate([
                threadTitleLabel.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                threadTitleLabel.rightAnchor.constraint(equalTo: self.subheaderPart.rightAnchor, constant: -10),
                threadTitleLabel.topAnchor.constraint(equalTo: self.subheaderPart.topAnchor, constant: 10),
                threadTitleLabel.bottomAnchor.constraint(equalTo: self.subheaderPart.bottomAnchor)
            ])
        }
    }

    // MARK: - QuotePart

    func showQuotePart() {
        self.quotePart.isHidden = false

        if self.quotedMessageView == nil {
            let quotedMessageView = QuotedMessageView()
            self.quotedMessageView = quotedMessageView

            quotedMessageView.translatesAutoresizingMaskIntoConstraints = false

            self.quotePart.addSubview(quotedMessageView)

            NSLayoutConstraint.activate([
                quotedMessageView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                quotedMessageView.rightAnchor.constraint(equalTo: self.quotePart.rightAnchor, constant: -10),
                quotedMessageView.topAnchor.constraint(equalTo: self.quotePart.topAnchor, constant: 10),
                quotedMessageView.bottomAnchor.constraint(equalTo: self.quotePart.bottomAnchor)
            ])

            let quoteTap = UITapGestureRecognizer(target: self, action: #selector(quoteTapped(_:)))
            quotedMessageView.addGestureRecognizer(quoteTap)
        }
    }

    @objc func quoteTapped(_ sender: UITapGestureRecognizer?) {
        if let parent = self.message?.parent {
            self.delegate?.cellWantsToScroll(to: parent)
        }
    }

    // MARK: - ReferencePart

    func showReferencePart() {
        self.referencePart.isHidden = false

        if self.referenceView == nil {
            let referenceView = ReferenceView()
            self.referenceView = referenceView

            referenceView.translatesAutoresizingMaskIntoConstraints = false

            self.referencePart.addSubview(referenceView)

            NSLayoutConstraint.activate([
                referenceView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                referenceView.rightAnchor.constraint(equalTo: self.referencePart.rightAnchor, constant: -10),
                referenceView.topAnchor.constraint(equalTo: self.referencePart.topAnchor),
                referenceView.bottomAnchor.constraint(equalTo: self.referencePart.bottomAnchor, constant: -5)
            ])
        }
    }

    // MARK: - ReactionsPart

    func showThreadRepliesButton() {
        self.threadRepliesButton.addAction { [weak self] in
            guard let self, let message else { return }
            self.delegate?.cellWants(toShowThread: message)
        }

        let replies = message?.threadReplies ?? 0
        if replies > 0 {
            let repliesString = String.localizedStringWithFormat(NSLocalizedString("%d replies", comment: "Replies in a thread"), replies)
            self.threadRepliesButton.setTitle(repliesString, for: .normal)
        } else {
            self.threadRepliesButton.setTitle("Reply", for: .normal)
        }

        self.reactionPart.isHidden = false
        self.threadRepliesButton.isHidden = false
    }

    func showReactionsPart() {
        self.reactionPart.isHidden = false

        if self.reactionView == nil {
            let flowLayout = UICollectionViewFlowLayout()
            flowLayout.scrollDirection = .horizontal

            let reactionView = ReactionsView(frame: .init(x: 0, y: 0, width: 50, height: 30), collectionViewLayout: flowLayout)
            reactionView.reactionsDelegate = self
            self.reactionView = reactionView

            reactionView.translatesAutoresizingMaskIntoConstraints = false

            self.reactionStackView.addArrangedSubview(reactionView)
        }
    }

    // MARK: - ReactionsView Delegate

    func didSelectReaction(reaction: NCChatReaction) {
        if let message = self.message {
            self.delegate?.cellDidSelectedReaction(reaction, for: message)
        }
    }

    // MARK: - Avatar User Menu

    func getDeferredUserMenu() -> UIMenu? {
        guard let message = self.message, let account = message.account
        else { return nil }

        if message.actorType != "users" || message.actorId == account.userId {
            return nil
        }

        // Use an uncached provider so local time is not cached
        let deferredMenuElement = UIDeferredMenuElement.uncached { [weak self] completion in
            self?.getMenuUserAction(for: message) { items in
                completion(items)
            }
        }

        return UIMenu(title: message.actorDisplayName, children: [deferredMenuElement])
    }

    func getMenuUserAction(for message: NCChatMessage, completionBlock: @escaping ([UIMenuElement]) -> Void) {
        guard let account = message.account else { return }

        NCAPIController.sharedInstance().getUserActions(forUser: message.actorId, using: account) { userActionsRaw, error in
            guard error == nil,
                  let userActionsDict = userActionsRaw as? [String: AnyObject],
                  let userActions = userActionsDict["actions"] as? [[String: String]],
                  let userId = userActionsDict["userId"] as? String
            else {
                let errorAction = UIAction(title: NSLocalizedString("No actions available", comment: "")) { _ in }
                errorAction.attributes = .disabled
                completionBlock([errorAction])

                return
            }

            var menuItems: [UIMenuElement] = []

            for userAction in userActions {
                guard let appId = userAction["appId"],
                      let title = userAction["title"],
                      let link = userAction["hyperlink"],
                      let linkEncoded = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                else { continue }

                if appId == "spreed" {
                    let talkAction = UIAction(title: title, image: UIImage(named: "talk-20")?.withRenderingMode(.alwaysTemplate)) { _ in
                        NotificationCenter.default.post(name: NSNotification.Name.NCChatViewControllerTalkToUserNotification, object: self, userInfo: ["actorId": userId])
                    }

                    menuItems.append(talkAction)
                    continue
                }

                let otherAction = UIAction(title: title) { _ in
                    if let actionUrl = URL(string: linkEncoded) {
                        UIApplication.shared.open(actionUrl)
                    }
                }

                if appId == "profile" {
                    otherAction.image = UIImage(systemName: "person")
                } else if appId == "email" {
                    otherAction.image = UIImage(systemName: "envelope")
                } else if appId == "timezone" {
                    otherAction.image = UIImage(systemName: "clock")
                } else if appId == "social" {
                    otherAction.image = UIImage(systemName: "heart")
                }

                menuItems.append(otherAction)
            }

            completionBlock(menuItems)
        }
    }

    // MARK: - File status / activity indicator

    func clearFileStatusView() {
            self.fileActivityIndicator?.stopAnimating()
            self.fileActivityIndicator?.removeFromSuperview()
            self.fileActivityIndicator = nil
    }

    func addActivityIndicator(with progress: Float) {
        self.clearFileStatusView()

        let fileActivityIndicator = MDCActivityIndicator(frame: .init(x: 0, y: 0, width: 20, height: 20))
        self.fileActivityIndicator = fileActivityIndicator

        fileActivityIndicator.radius = 6
        fileActivityIndicator.strokeWidth = 1.5
        fileActivityIndicator.cycleColors = [.secondaryLabel]

        if progress > 0 {
            fileActivityIndicator.indicatorMode = .determinate
            fileActivityIndicator.setProgress(progress, animated: false)
        }

        fileActivityIndicator.startAnimating()
        fileActivityIndicator.widthAnchor.constraint(equalToConstant: 20).isActive = true
        self.statusView.addArrangedSubview(fileActivityIndicator)
    }

    // MARK: - File notifications

    @objc func didChangeIsDownloading(notification: Notification) {
        DispatchQueue.main.async {
            // Make sure this notification is really for this cell
            guard let fileParameter = self.message?.file(),
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
            else { return }

            if receivedStatus.isDownloading, self.fileActivityIndicator == nil {
                // Immediately show an indeterminate indicator as long as we don't have a progress value
                self.addActivityIndicator(with: 0)
            } else if !receivedStatus.isDownloading, self.fileActivityIndicator != nil {
                self.clearFileStatusView()
            }
        }
    }

    @objc func didChangeDownloadProgress(notification: Notification) {
        DispatchQueue.main.async {
            // Make sure this notification is really for this cell
            guard let fileParameter = self.message?.file(),
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
            else { return }

            if self.fileActivityIndicator != nil {
                // Switch to determinate-mode and show progress
                if receivedStatus.canReportProgress {
                    self.fileActivityIndicator?.indicatorMode = .determinate
                    self.fileActivityIndicator?.setProgress(Float(receivedStatus.downloadProgress), animated: true)
                }
            } else {
                // Make sure we have an activity indicator added to this cell
                self.addActivityIndicator(with: Float(receivedStatus.downloadProgress))
            }
        }
    }
}
