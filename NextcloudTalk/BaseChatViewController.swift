//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import NextcloudKit
import PhotosUI
import UIKit
import Realm
import ContactsUI
import QuickLook
import SwiftUI

@objcMembers public class BaseChatViewController: InputbarViewController,
                                                  UITextFieldDelegate,
                                                  UIImagePickerControllerDelegate,
                                                  UIAdaptivePresentationControllerDelegate,
                                                  PHPickerViewControllerDelegate,
                                                  UINavigationControllerDelegate,
                                                  ShareLocationViewControllerDelegate,
                                                  CNContactPickerDelegate,
                                                  UIDocumentPickerDelegate,
                                                  VLCKitVideoViewControllerDelegate,
                                                  ShareViewControllerDelegate,
                                                  QLPreviewControllerDelegate,
                                                  QLPreviewControllerDataSource,
                                                  NCChatFileControllerDelegate,
                                                  ShareConfirmationViewControllerDelegate,
                                                  AVAudioRecorderDelegate,
                                                  AVAudioPlayerDelegate,
                                                  SystemMessageTableViewCellDelegate,
                                                  BaseChatTableViewCellDelegate,
                                                  UITableViewDataSourcePrefetching,
                                                  MessageSeparatorTableViewCellDelegate,
                                                  DateHeaderViewDelegate {

    // MARK: - Internal var
    internal var messages: [Date: [NCChatMessage]] = [:]
    internal var dateSections: [Date] = []

    internal var isVisible = false
    internal var isTyping = false
    internal var firstUnreadMessage: NCChatMessage?
    internal var dismissNotificationsOnViewWillDisappear = true

    internal var replyMessageView: ReplyMessageView?
    internal var voiceMessagesPlayer: AVAudioPlayer?
    internal var interactingMessage: NCChatMessage?
    internal var lastMessageBeforeInteraction: IndexPath?
    internal var contextMenuActionBlock: (() -> Void)?
    internal var editingMessage: NCChatMessage?

    internal lazy var emojiTextField: EmojiTextField = {
        let emojiTextField = EmojiTextField()
        emojiTextField.delegate = self

        self.view.addSubview(emojiTextField)

        return emojiTextField
    }()

    internal lazy var datePickerTextField: DatePickerTextField = {
        let datePicker = DatePickerTextField()
        datePicker.delegate = self

        self.view.addSubview(datePicker)

        return datePicker
    }()

    internal lazy var chatBackgroundView: PlaceholderView = {
        let chatBackgroundView = PlaceholderView(for: .insetGrouped)!
        chatBackgroundView.placeholderView.isHidden = true
        chatBackgroundView.loadingView.startAnimating()
        chatBackgroundView.placeholderTextView.text = NSLocalizedString("No messages yet, start the conversation!", comment: "")
        chatBackgroundView.setImage(UIImage(named: "chat-placeholder"))
        chatBackgroundView.accessibilityIdentifier = "Chat PlacerholderView"

        return chatBackgroundView
    }()

    // MARK: - Private var
    private var sendButtonTagMessage = 99
    private var sendButtonTagVoice = 98

    private var isVoiceRecordingLocked = false

    private var actionTypeTranscribeVoiceMessage = "transcribe-voice-message"

    private var imagePicker: UIImagePickerController?

    private var stopTypingTimer: Timer?
    private var typingTimer: Timer?
    private var voiceMessageLongPressGesture: UILongPressGestureRecognizer?
    private var recorder: AVAudioRecorder?
    private var voiceMessageRecordingView: VoiceMessageRecordingView?
    private var expandedUIHostingController: UIHostingController<ExpandedVoiceMessageRecordingView>?
    private var longPressStartingPoint: CGPoint?
    private var cancelHintLabelInitialPositionX: CGFloat?
    private var recordCancelled: Bool = false

    private var animationDispatchGroup = DispatchGroup()
    private var animationDispatchQueue = DispatchQueue(label: "\(groupIdentifier).animationQueue")

    private var loadingHistoryView: UIActivityIndicatorView?

    private var isPreviewControllerShown: Bool = false
    private var previewControllerFilePath: String?

    private var playerProgressTimer: Timer?
    private var playerAudioFileStatus: NCChatFileStatus?

    private var photoPicker: PHPickerViewController?

    private var contextMenuAccessoryView: UIView?
    private var contextMenuMessageView: UIView?

    private var leftButtonLongPressGesture: UILongPressGestureRecognizer?

    private lazy var inputbarBorderView: UIView = {
        let inputbarBorderView = UIView()
        inputbarBorderView.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        inputbarBorderView.frame = .init(x: 0, y: 0, width: self.textInputbar.frame.size.width, height: 1)
        inputbarBorderView.isHidden = true
        inputbarBorderView.backgroundColor = .quaternarySystemFill

        self.textInputbar.addSubview(inputbarBorderView)

        return inputbarBorderView
    }()

    private lazy var unreadMessageButton: UIButton = {
        let unreadMessageButton = UIButton(frame: .init(x: 0, y: 0, width: 280, height: 60))

        unreadMessageButton.backgroundColor = NCAppBranding.themeColor()
        unreadMessageButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
        unreadMessageButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .footnote)
        unreadMessageButton.layer.cornerRadius = 8
        unreadMessageButton.clipsToBounds = true
        unreadMessageButton.isHidden = true
        unreadMessageButton.translatesAutoresizingMaskIntoConstraints = false
        unreadMessageButton.contentEdgeInsets = .init(top: 6, left: 12, bottom: 6, right: 12)
        unreadMessageButton.titleLabel?.minimumScaleFactor = 0.7
        unreadMessageButton.titleLabel?.numberOfLines = 1
        unreadMessageButton.titleLabel?.adjustsFontSizeToFitWidth = true
        unreadMessageButton.setTitle(NSLocalizedString("↓ New messages", comment: ""), for: .normal)

        unreadMessageButton.addAction { [weak self] in
            guard let self,
                  let firstUnreadMessage = self.firstUnreadMessage,
                  let indexPath = self.indexPath(for: firstUnreadMessage)
            else { return }

            self.tableView?.scrollToRow(at: indexPath, at: .none, animated: true)
        }

        self.view.addSubview(unreadMessageButton)

        return unreadMessageButton
    }()

    private lazy var scrollToBottomButton: UIButton = {
        let button = UIButton(frame: .init(x: 0, y: 0, width: 44, height: 44), primaryAction: UIAction { [weak self] _ in
            self?.tableView?.slk_scrollToBottom(animated: true)
        })

        button.backgroundColor = .secondarySystemGroupedBackground
        button.tintColor = .systemBlue
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
        button.alpha = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)

        self.view.addSubview(button)

        return button
    }()

    private lazy var voiceRecordingLockButton: UIButton = {
        let button = UIButton(frame: .init(x: 0, y: 0, width: 44, height: 44))

        button.backgroundColor = .secondarySystemGroupedBackground
        button.tintColor = .systemBlue
        button.layer.cornerRadius = button.frame.size.height / 2
        button.clipsToBounds = true
        button.alpha = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "lock.open"), for: .normal)

        self.view.addSubview(button)

        return button
    }()

    // MARK: - Init/Deinit

    public init?(forRoom room: NCRoom, withAccount account: TalkAccount) {
        super.init(forRoom: room, withAccount: account, tableViewStyle: .plain)

        self.hidesBottomBarWhenPushed = true
        self.tableView?.estimatedRowHeight = 0
        self.tableView?.estimatedSectionHeaderHeight = 0
        self.tableView?.prefetchDataSource = self

        NotificationCenter.default.addObserver(self, selector: #selector(willShowKeyboard(notification:)), name: UIWindow.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willHideKeyboard(notification:)), name: UIWindow.keyboardWillHideNotification, object: nil)

        AllocationTracker.shared.addAllocation("ChatViewController")
    }

    // Not using an optional here, because it is not available from ObjC
    // Pass "0" as highlightMessageId to not highlight a message
    public convenience init?(forRoom room: NCRoom, withAccount account: TalkAccount, withMessage messages: [NCChatMessage], withHighlightId highlightMessageId: Int) {
        self.init(forRoom: room, withAccount: account)

        // When we pass in a fixed number of messages, we hide the inputbar by default
        self.textInputbar.isHidden = true

        // Scroll to bottom manually after hiding the textInputbar, otherwise the
        // scrollToBottom button might be briefly visible even if not needed
        self.tableView?.slk_scrollToBottom(animated: false)

        self.appendMessages(messages: messages)

        self.tableView?.performBatchUpdates({
            self.tableView?.reloadData()
        }, completion: { _ in
            self.highlightMessageWithContentOffset(messageId: highlightMessageId)
        })
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        AllocationTracker.shared.removeAllocation("ChatViewController")
        NSLog("Dealloc BaseChatViewController")
    }

    // MARK: - View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.shouldScrollToBottomAfterKeyboardShows = false
        self.isInverted = false

        self.showSendMessageButton()
        self.leftButton.setImage(UIImage(systemName: "plus"), for: .normal)
        self.leftButton.accessibilityLabel = NSLocalizedString("Share a file from your Nextcloud", comment: "")
        self.leftButton.accessibilityHint = NSLocalizedString("Double tap to open file browser", comment: "")
        self.leftButton.accessibilityIdentifier = "shareButton"

        // Add LongPressRecognizer to allow showing photo picker directly
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPress(gestureRecognizer:)))
        self.leftButtonLongPressGesture = longPressRecognizer
        self.leftButton.addGestureRecognizer(longPressRecognizer)

        // Set delegate to retrieve typing events
        self.tableView?.separatorStyle = .none

        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: chatMessageCellIdentifier)
        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: chatGroupedMessageCellIdentifier)
        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: chatReplyMessageCellIdentifier)

        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: fileMessageCellIdentifier)
        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: fileGroupedMessageCellIdentifier)

        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: locationMessageCellIdentifier)
        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: locationGroupedMessageCellIdentifier)

        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: voiceMessageCellIdentifier)
        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: voiceGroupedMessageCellIdentifier)

        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: pollMessageCellIdentifier)
        self.tableView?.register(UINib(nibName: "BaseChatTableViewCell", bundle: nil), forCellReuseIdentifier: pollGroupedMessageCellIdentifier)

        self.tableView?.register(SystemMessageTableViewCell.self, forCellReuseIdentifier: SystemMessageCellIdentifier)
        self.tableView?.register(MessageSeparatorTableViewCell.self, forCellReuseIdentifier: MessageSeparatorTableViewCell.identifier)

        let newMessagesButtonText = NSLocalizedString("↓ New messages", comment: "")

        // Need to move down to NSLayout
        let attributes = [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .footnote)]
        let textSize = NSString(string: newMessagesButtonText).boundingRect(with: .init(width: 280, height: 60), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        let buttonWidth = textSize.size.width + 24

        let views = [
            "unreadMessageButton": self.unreadMessageButton,
            "textInputbar": self.textInputbar,
            "scrollToBottomButton": self.scrollToBottomButton,
            "autoCompletionView": self.autoCompletionView,
            "voiceRecordingLockButton": self.voiceRecordingLockButton
        ]

        let metrics = [
            "buttonWidth": buttonWidth
        ]

        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[unreadMessageButton]-10-[autoCompletionView]", metrics: metrics, views: views))
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=0)-[unreadMessageButton(buttonWidth)]-(>=0)-|", metrics: metrics, views: views))

        if let view = self.view {
            self.view.addConstraint(NSLayoutConstraint(item: view, attribute: .centerX, relatedBy: .equal, toItem: self.unreadMessageButton, attribute: .centerX, multiplier: 1, constant: 0))
        }

        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[scrollToBottomButton(44)]-10-[autoCompletionView]", metrics: metrics, views: views))
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=0)-[scrollToBottomButton(44)]-(>=0)-|", metrics: metrics, views: views))

        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[voiceRecordingLockButton(44)]-64-[autoCompletionView]", metrics: metrics, views: views))
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=0)-[voiceRecordingLockButton(44)]-(>=0)-|", metrics: metrics, views: views))

        self.scrollToBottomButton.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10).isActive = true
        self.voiceRecordingLockButton.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10).isActive = true

        self.addMenuToLeftButton()

        self.replyMessageView?.addObserver(self, forKeyPath: "visible", options: .new, context: nil)

        self.textView.pastableMediaTypes = .images

        // Allow pasting Memojis and Genmojis
        self.textView.allowsEditingTextAttributes = true
        if #available(iOS 18.0, *) {
            self.textView.supportsAdaptiveImageGlyph = true
        }
    }

    // swiftlint:disable:next block_based_kvo
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)

        guard let object = object as? ReplyMessageView,
              object == self.replyMessageView else { return }

        // When the visible state of the replyMessageView changes, we need to update the toolbar to show the correct border
        // Only do this if we are not already at the bottom, otherwise we briefly show the scroll button directly after sending a message
        self.updateToolbar(animated: true)
    }

    public func updateToolbar(animated: Bool) {
        guard let tableView else { return }

        let animations = {
            let minimumOffset = (tableView.contentSize.height - tableView.frame.size.height) - 10

            if tableView.contentOffset.y < minimumOffset {
                // Scrolled -> show top border

                // When a reply view is visible, we show the border of that view
                if let replyMessageView = self.replyMessageView {
                    replyMessageView.topBorder.isHidden = !replyMessageView.isVisible
                    self.inputbarBorderView.isHidden = replyMessageView.isVisible
                } else {
                    self.inputbarBorderView.isHidden = false
                }
            } else {
                // At the bottom -> no top border
                self.inputbarBorderView.isHidden = true

                if let replyMessageView = self.replyMessageView {
                    replyMessageView.topBorder.isHidden = true
                }
            }
        }

        let animationsScrollButton = {
            let minimumOffset = (tableView.contentSize.height - tableView.frame.size.height) - 10

            if tableView.contentOffset.y < minimumOffset {
                // Scrolled -> show button
                self.scrollToBottomButton.alpha = 1
            } else {
                // At the bottom -> hide button
                self.scrollToBottomButton.alpha = 0
            }
        }

        if animated {
            self.animationDispatchQueue.async {
                self.animationDispatchGroup.enter()
                self.animationDispatchGroup.enter()

                DispatchQueue.main.async {
                    UIView.transition(with: self.textInputbar,
                                      duration: 0.3,
                                      options: .transitionCrossDissolve,
                                      animations: animations) { _ in
                        self.animationDispatchGroup.leave()
                    }
                }

                DispatchQueue.main.async {
                    UIView.animate(withDuration: 0.3,
                                   animations: animationsScrollButton) { _ in
                        self.animationDispatchGroup.leave()
                    }
                }

                _ = self.animationDispatchGroup.wait(timeout: .distantFuture)
            }
        } else {
            DispatchQueue.main.async {
                animations()
                animationsScrollButton()
            }
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.isVisible = true
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.isVisible = false

        if !self.textInputbar.isHidden {
            self.savePendingMessage()
        }

        if dismissNotificationsOnViewWillDisappear {
            NotificationPresenter.shared().dismiss(animated: false)
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            self.updateToolbar(animated: true)
        }

        if self.traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass,
           let indexPath = self.indexPathForUnreadMessageSeparator() {

            DispatchQueue.main.async {
                self.tableView?.reloadRows(at: [indexPath], with: .none)
            }
        }
    }

    // MARK: - Keyboard notifications

    func willShowKeyboard(notification: Notification) {
        guard let currentResponder = UIResponder.slk_currentFirst() else { return }

        // Skip if it's not the emoji/date text field
        if !currentResponder.isKind(of: EmojiTextField.self) && !currentResponder.isKind(of: DatePickerTextField.self) {
            return
        }

        guard let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }

        let keyboardRect = keyboardFrame.cgRectValue
        self.updateView(toShowOrHideEmojiKeyboard: keyboardRect.size.height)

        guard let interactingMessage,
              let indexPath = self.indexPath(for: interactingMessage) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            if let tableView = self.tableView {
                let cellRect = tableView.rectForRow(at: indexPath)

                if !tableView.bounds.contains(cellRect) {
                    self.tableView?.scrollToRow(at: indexPath, at: .bottom, animated: true)
                }
            }
        }
    }

    func willHideKeyboard(notification: Notification) {
        guard let currentResponder = UIResponder.slk_currentFirst() else { return }

        // Skip if it's not the emoji/date text field
        if !currentResponder.isKind(of: EmojiTextField.self) && !currentResponder.isKind(of: DatePickerTextField.self) {
            return
        }

        self.updateView(toShowOrHideEmojiKeyboard: 0.0)

        guard let lastMessageBeforeInteraction, let tableView else { return }

        if tableView.isValid(indexPath: lastMessageBeforeInteraction) {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                tableView.scrollToRow(at: lastMessageBeforeInteraction, at: .bottom, animated: true)
            }
        }
    }

    // MARK: - Utils

    internal func getHeaderString(fromDate date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.doesRelativeDateFormatting = true

        return formatter.string(from: date)
    }

    internal func presentWithNavigation(_ viewControllerToPresent: UIViewController, animated flag: Bool) {
        self.present(NCNavigationController(rootViewController: viewControllerToPresent), animated: flag)
    }

    // MARK: - Temporary messages

    internal func createTemporaryMessage(message: String, replyTo parentMessage: NCChatMessage?, messageParameters: String, silently: Bool, isVoiceMessage: Bool) -> NCChatMessage? {
        let temporaryMessage = NCChatMessage()

        temporaryMessage.accountId = self.account.accountId
        temporaryMessage.actorDisplayName = self.account.userDisplayName
        temporaryMessage.actorId = self.account.userId
        temporaryMessage.actorType = "users"
        temporaryMessage.timestamp = Int(Date().timeIntervalSince1970)
        temporaryMessage.token = room.token
        temporaryMessage.threadId = thread?.threadId ?? 0
        temporaryMessage.isThread = thread != nil

        let referenceId = "temp-\(Date().timeIntervalSince1970 * 1000)"
        temporaryMessage.referenceId = NCUtils.sha1(fromString: referenceId)
        temporaryMessage.internalId = referenceId
        temporaryMessage.isTemporary = true
        temporaryMessage.parentId = parentMessage?.internalId

        if isVoiceMessage {
            var messageParametersDict = [String: Any]()
            let parameterId = UUID().uuidString

            temporaryMessage.message = message
            temporaryMessage.messageType = kMessageTypeVoiceMessage

            let fileParameterDict: [String: Any] = [
                "id": parameterId,
                "type": "file",
                "name": message,
                "path": messageParameters,
                "fileId": parameterId,
                "fileName": message,
                "filePath": messageParameters,
                "fileLocalPath": messageParameters
            ]

            messageParametersDict["file"] = fileParameterDict

            if let jsonData = try? JSONSerialization.data(withJSONObject: messageParametersDict, options: []) {
                let messageParametersJSONString = String(data: jsonData, encoding: .utf8) ?? ""
                temporaryMessage.messageParametersJSONString = messageParametersJSONString
            }
        } else {
            temporaryMessage.messageParametersJSONString = messageParameters
            temporaryMessage.message = self.replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: message, parameters: messageParameters)
        }
        temporaryMessage.isSilent = silently
        temporaryMessage.isMarkdownMessage = NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityMarkdownMessages, for: self.room)

        let realm = RLMRealm.default()

        try? realm.transaction {
            realm.add(temporaryMessage)
        }

        let unmanagedTemporaryMessage = NCChatMessage(value: temporaryMessage)
        return unmanagedTemporaryMessage
    }

    internal func appendTemporaryMessage(temporaryMessage: NCChatMessage) {
        DispatchQueue.main.async {
            let lastSectionBeforeUpdate = self.dateSections.count - 1

            self.appendMessages(messages: [temporaryMessage])

            if let lastDateSection = self.dateSections.last, let messagesForLastDate = self.messages[lastDateSection] {
                let lastMessageIndexPath = IndexPath(row: messagesForLastDate.count - 1, section: self.dateSections.count - 1)

                self.tableView?.beginUpdates()

                let newLastSection = self.dateSections.count - 1
                if lastSectionBeforeUpdate != newLastSection {
                    self.tableView?.insertSections(.init(integer: newLastSection), with: .none)
                } else {
                    self.tableView?.insertRows(at: [lastMessageIndexPath], with: .none)
                }

                self.tableView?.endUpdates()
                self.tableView?.scrollToRow(at: lastMessageIndexPath, at: .none, animated: true)
            }
        }
    }

    internal func removePermanentlyTemporaryMessage(temporaryMessage: NCChatMessage) {
        let realm = RLMRealm.default()

        try? realm.transaction {
            if let managedTemporaryMessage = NCChatMessage.objects(where: "referenceId = %@ AND isTemporary = true", temporaryMessage.referenceId).firstObject() {
                realm.delete(managedTemporaryMessage)
            }
        }

        self.removeTemporaryMessages(temporaryMessages: [temporaryMessage])
    }

    internal func removeTemporaryMessages(temporaryMessages: [NCChatMessage]) {
        DispatchQueue.main.async {
            for temporaryMessage in temporaryMessages {
                if let indexPath = self.indexPath(for: temporaryMessage) {
                    self.removeMessage(at: indexPath)
                }
            }
        }
    }

    // MARK: - Message updates

    internal func modifyMessageWith(referenceId: String, block: (NCChatMessage) -> Void) {
        guard let (indexPath, message) = self.indexPathAndMessage(forReferenceId: referenceId)
        else { return }

        block(message)

        self.tableView?.beginUpdates()
        self.tableView?.reloadRows(at: [indexPath], with: .none)
        self.tableView?.endUpdates()
    }

    internal func updateMessage(withMessageId messageId: Int, updatedMessage: NCChatMessage) {
        DispatchQueue.main.async {
            guard let (indexPath, message) = self.indexPathAndMessage(forMessageId: messageId) else { return }
            var reloadIndexPaths = [indexPath]

            let isAtBottom = self.shouldScrollOnNewMessages()
            let keyDate = self.dateSections[indexPath.section]
            updatedMessage.isGroupMessage = message.isGroupMessage && message.actorType != "bots" && updatedMessage.lastEditTimestamp == 0
            self.messages[keyDate]?[indexPath.row] = updatedMessage

            // Check if there are any messages that reference our message as a parent -> these need to be reloaded as well
            if let visibleIndexPaths = self.tableView?.indexPathsForVisibleRows {
                let referencingIndexPaths = visibleIndexPaths.filter({
                    guard let message = self.message(for: $0),
                          let parentMessage = message.parent
                    else { return false }

                    return parentMessage.messageId == messageId
                })

                reloadIndexPaths.append(contentsOf: referencingIndexPaths)
            }

            self.tableView?.beginUpdates()
            self.tableView?.reloadRows(at: reloadIndexPaths, with: .none)
            self.tableView?.endUpdates()

            if isAtBottom {
                // Make sure we're really at the bottom after updating a message
                DispatchQueue.main.async {
                    self.tableView?.slk_scrollToBottom(animated: false)
                    self.updateToolbar(animated: false)
                }
            }
        }
    }

    internal func updateThreadOriginalMessage(withMessage message: NCChatMessage) {
        DispatchQueue.main.async {
            guard let (indexPath, originalThreadMessage) = self.getThreadOriginalMessage(forThreadId: message.threadId) else { return }

            originalThreadMessage.threadTitle = message.threadTitle
            originalThreadMessage.threadReplies = message.threadReplies

            self.tableView?.beginUpdates()
            self.tableView?.reloadRows(at: [indexPath], with: .none)
            self.tableView?.endUpdates()
        }
    }

    // MARK: - User interface

    func showVoiceMessageRecordButton() {
        self.rightButton.setTitle("", for: .normal)
        self.rightButton.setImage(UIImage(systemName: "mic"), for: .normal)
        self.rightButton.tag = sendButtonTagVoice
        self.rightButton.accessibilityLabel = NSLocalizedString("Record voice message", comment: "")
        self.rightButton.accessibilityHint = NSLocalizedString("Tap and hold to record a voice message", comment: "")

        self.addGestureRecognizerToRightButton()
    }

    func showSendMessageButton() {
        self.rightButton.setTitle("", for: .normal)
        self.rightButton.setImage(UIImage(systemName: "paperplane"), for: .normal)
        self.rightButton.tag = sendButtonTagMessage
        self.rightButton.accessibilityLabel = NSLocalizedString("Send message", comment: "")
        self.rightButton.accessibilityHint = NSLocalizedString("Double tap to send message", comment: "")

        self.addMenuToRightButton()
    }

    // MARK: - Action methods

    func sendChatMessage(message: String, withParentMessage parentMessage: NCChatMessage?, messageParameters: String, silently: Bool) {
        // Overridden in sub class
    }

    func sendCurrentMessage(silently: Bool) {
        var replyToMessage: NCChatMessage?

        if let replyMessageView, replyMessageView.isVisible {
            replyToMessage = replyMessageView.message
        }

        let messageParameters = NCMessageParameter.messageParametersJSONString(from: self.mentionsDict) ?? ""
        self.sendChatMessage(message: self.textView.text, withParentMessage: replyToMessage, messageParameters: messageParameters, silently: silently)

        self.mentionsDict.removeAll()
        self.replyMessageView?.dismiss()
        super.didPressRightButton(self)
        self.clearPendingMessage()
        self.stopTyping(force: true)
    }

    public override func didPressRightButton(_ sender: Any?) {
        guard let button = sender as? UIButton else { return }

        switch button.tag {
        case sendButtonTagMessage:
            self.sendCurrentMessage(silently: false)
            super.didPressRightButton(sender)
        case sendButtonTagVoice:
            self.showVoiceMessageRecordHint()
        default:
            break
        }
    }

    func addGestureRecognizerToRightButton() {
        // Remove a potential menu so it does not interfere with the long gesture recognizer
        self.rightButton.menu = nil

        // Add long press gesture recognizer for voice message recording button
        self.voiceMessageLongPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressInVoiceMessageRecordButton(gestureRecognizer:)))

        if let voiceMessageLongPressGesture {
            voiceMessageLongPressGesture.delegate = self
            self.rightButton.addGestureRecognizer(voiceMessageLongPressGesture)
        }
    }

    func addMenuToRightButton() {
        // Remove a gesture recognizer to not interfere with our menu
        if let voiceMessageLongPressGesture = self.voiceMessageLongPressGesture {
            self.rightButton.removeGestureRecognizer(voiceMessageLongPressGesture)
            self.voiceMessageLongPressGesture = nil
        }

        let silentSendAction = UIAction(title: NSLocalizedString("Send without notification", comment: ""), image: UIImage(systemName: "bell.slash")) { [unowned self] _ in
            self.sendCurrentMessage(silently: true)
        }

        self.rightButton.menu = UIMenu(children: [silentSendAction])
    }

    func addMenuToLeftButton() {
        // The keyboard will be hidden when an action is invoked. Depending on what
        // attachment is shared, not resigning might lead to a currupted chat view
        var items: [UIMenuElement] = []

        let cameraAction = UIAction(title: NSLocalizedString("Camera", comment: ""), image: UIImage(systemName: "camera")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.checkAndPresentCamera()
        }

        let photoLibraryAction = UIAction(title: NSLocalizedString("Photo Library", comment: ""), image: UIImage(systemName: "photo")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentPhotoLibrary()
        }

        let shareLocationAction = UIAction(title: NSLocalizedString("Location", comment: ""), image: UIImage(systemName: "location")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentShareLocation()
        }

        let contactShareAction = UIAction(title: NSLocalizedString("Contacts", comment: ""), image: UIImage(systemName: "person")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentShareContact()
        }

        let filesAction = UIAction(title: NSLocalizedString("Files", comment: ""), image: UIImage(systemName: "doc")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentDocumentPicker()
        }

        let ncFilesAction = UIAction(title: filesAppName, image: UIImage(named: "logo-action")?.withRenderingMode(.alwaysTemplate)) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentNextcloudFilesBrowser()
        }

        let pollAction = UIAction(title: NSLocalizedString("Poll", comment: ""), image: UIImage(systemName: "chart.bar")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentPollCreation()
        }

        let threadAction = UIAction(title: NSLocalizedString("Thread", comment: ""), image: UIImage(systemName: "bubble.left.and.bubble.right")) { [unowned self] _ in
            self.textView.resignFirstResponder()
            self.presentThreadCreation()
        }

        // Add actions (inverted)
        var objectItems = [UIMenuElement]()
        objectItems.append(contactShareAction)

        if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityLocationSharing, for: self.room) {
            objectItems.append(shareLocationAction)
        }

        if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityTalkPolls, for: self.room),
            self.room.type != .oneToOne, self.room.type != .noteToSelf {

            objectItems.append(pollAction)
        }

        if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityThreads, for: self.room),
           self.thread == nil {

            objectItems.append(threadAction)
        }

        // TODO: Remove this check when rich objects and polls can be shared in threads
        if thread == nil {
            items.append(UIMenu(options: .displayInline, children: objectItems))
        }

        items.append(ncFilesAction)
        items.append(filesAction)

        items.append(photoLibraryAction)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            items.append(cameraAction)
        }

        self.leftButton.menu = UIMenu(children: items)
        self.leftButton.showsMenuAsPrimaryAction = true

        // Ensure that our longPressGestureRecognizer does not interfere with the native ones
        _ = self.leftButton.gestureRecognizers?.map { recognizer in
            if let leftButtonLongPressGesture {
                recognizer.require(toFail: leftButtonLongPressGesture)
            }
        }
    }

    func longPress(gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began else { return }

        // Remove the menu, so we don't accidentially open the menu on a long press
        self.leftButton.menu = nil

        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()

        self.presentPhotoLibrary()

        // Re-add the menu to the left button
        self.addMenuToLeftButton()
    }

    func presentNextcloudFilesBrowser() {
        let directoryVC = DirectoryTableViewController(path: "", inRoom: self.room.token, andThread: self.thread?.threadId ?? 0)
        self.presentWithNavigation(directoryVC, animated: true)
    }

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
        NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
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
        DispatchQueue.main.async {
            var pickerConfig = PHPickerConfiguration()
            pickerConfig.selectionLimit = 5
            pickerConfig.filter = PHPickerFilter.any(of: [.images, .videos])

            self.photoPicker = PHPickerViewController(configuration: pickerConfig)

            if let photoPicker = self.photoPicker {
                photoPicker.delegate = self
                self.present(photoPicker, animated: true)
            }
        }
    }

    func presentThreadCreation() {
        if let threadCreationVC = ThreadCreationViewController(room: room, account: account) {
            self.present(threadCreationVC, animated: true)
        }
    }

    func presentPollCreation() {
        let pollCreationVC = PollCreationViewController(room: room)
        self.presentWithNavigation(pollCreationVC, animated: true)
    }

    func presentShareLocation() {
        let shareLocationVC = ShareLocationViewController()
        shareLocationVC.delegate = self
        self.presentWithNavigation(shareLocationVC, animated: true)
    }

    func presentShareContact() {
        let contactPicker = CNContactPickerViewController()
        contactPicker.delegate = self
        self.present(contactPicker, animated: true)
    }

    func presentDocumentPicker() {
        DispatchQueue.main.async {
            let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            documentPicker.delegate = self
            self.present(documentPicker, animated: true)
        }
    }

    func showReplyView(for message: NCChatMessage) {
        let isAtBottom = self.shouldScrollOnNewMessages()

        if let replyProxyView = self.replyProxyView as? ReplyMessageView {
            self.replyMessageView = replyProxyView

            replyProxyView.presentReply(with: message, withUserId: self.account.userId)
            self.presentKeyboard(true)

            // Make sure we're really at the bottom after showing the replyMessageView
            if isAtBottom {
                self.tableView?.slk_scrollToBottom(animated: false)
                self.updateToolbar(animated: false)
            }
        }
    }

    func didPressShowThread(for message: NCChatMessage, toReply: Bool = false) {
        // Overridden in sub class
    }

    func didPressReply(for message: NCChatMessage) {
        // Make sure we get a smooth animation after dismissing the context menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // If user press reply on the thread original message (in a normal chat view), open the thread view
            if self.thread == nil && message.isThreadOriginalMessage() {
                self.didPressShowThread(for: message, toReply: true)
                return
            }

            self.showReplyView(for: message)
        }
    }

    func didPressReplyPrivately(for message: NCChatMessage) {
        var userInfo: [String: String] = [:]
        userInfo["actorId"] = message.actorId
        NotificationCenter.default.post(name: .NCChatViewControllerReplyPrivatelyNotification, object: self, userInfo: userInfo)
    }

    func didPressAddReaction(for message: NCChatMessage, at indexPath: IndexPath) {
        // Hide the keyboard because we are going to present the emoji keyboard
        DispatchQueue.main.async {
            self.textView.resignFirstResponder()
        }

        DispatchQueue.main.async {
            self.interactingMessage = message
            self.lastMessageBeforeInteraction = self.tableView?.indexPathsForVisibleRows?.last

            if NCUtils.isiOSAppOnMac() {
                // Move the emojiTextField to the position of the cell
                if let rowRect = self.tableView?.rectForRow(at: indexPath),
                   var convertedRowRect = self.tableView?.convert(rowRect, to: self.view) {

                    // Show the emoji picker at the textView location of the cell
                    convertedRowRect.origin.y += convertedRowRect.size.height - 16
                    convertedRowRect.origin.x += 54

                    // We don't want to have a clickable textField floating around
                    convertedRowRect.size.width = 0
                    convertedRowRect.size.height = 0

                    // Remove and add the emojiTextField to the view, so the Mac OS emoji picker is always at the right location
                    self.emojiTextField.removeFromSuperview()
                    self.emojiTextField.frame = convertedRowRect
                    self.view.addSubview(self.emojiTextField)
                }
            }

            self.emojiTextField.becomeFirstResponder()
        }
    }

    func didPressForward(for message: NCChatMessage) {
        var shareViewController: ShareViewController

        if message.isObjectShare {
            shareViewController = ShareViewController(toForwardObjectShare: message, fromChatViewController: self)
        } else {
            shareViewController = ShareViewController(toForwardMessage: message.parsedMessage().string, fromChatViewController: self)
        }

        shareViewController.delegate = self
        self.presentWithNavigation(shareViewController, animated: true)
    }

    func didPressNoteToSelf(for message: NCChatMessage) {
        NCAPIController.sharedInstance().getNoteToSelfRoom(forAccount: self.account) { roomDict, error in
            if error == nil, let room = NCRoom(dictionary: roomDict, andAccountId: self.account.accountId) {

                if message.isObjectShare {
                    NCAPIController.sharedInstance().shareRichObject(message.richObjectFromObjectShare, inRoom: room.token, for: self.account) { error in
                        if error == nil {
                            NotificationPresenter.shared().present(text: NSLocalizedString("Added note to self", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                        } else {
                            NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while adding note", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                        }
                    }
                } else {
                    NCAPIController.sharedInstance().sendChatMessage(message.parsedMessage().string, toRoom: room.token, threadTitle: nil, replyTo: -1, referenceId: nil, silently: false, for: self.account) { error in
                        if error == nil {
                            NotificationPresenter.shared().present(text: NSLocalizedString("Added note to self", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                        } else {
                            NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while adding note", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                        }
                    }
                }
            } else {
                NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while adding note", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }
        }
    }

    func didPressResend(for message: NCChatMessage) {
        // Make sure there's no unread message separator, as the indexpath could be invalid after removing a message
        self.removeUnreadMessagesSeparator()

        self.removePermanentlyTemporaryMessage(temporaryMessage: message)

        guard let originalMessage = message.sendingMessageWithDisplayNames else { return }

        if message.messageType != kMessageTypeVoiceMessage {
            self.sendChatMessage(message: originalMessage, withParentMessage: message.parent, messageParameters: message.messageParametersJSONString ?? "", silently: message.isSilent)
        } else {
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityChatReferenceId, for: room) {
                self.appendTemporaryMessage(temporaryMessage: message)
            }
            NCAPIController.sharedInstance().uniqueNameForFileUpload(withName: originalMessage, originalName: true, for: activeAccount, withCompletionBlock: { fileServerURL, fileServerPath, _, _ in
                if let fileServerURL, let fileServerPath {
                    var talkMetaData: [String: Any] = ["messageType": "voice-message"]

                    if message.parentMessageId > 0 {
                        talkMetaData["replyTo"] = message.parentMessageId
                    }

                    if let thread = self.thread {
                        talkMetaData["threadId"] = thread.threadId
                    }

                    self.uploadFileAtPath(localPath: message.file().fileStatus!.fileLocalPath!, withFileServerURL: fileServerURL, andFileServerPath: fileServerPath, withMetaData: talkMetaData, temporaryMessage: message)
                } else {
                    NSLog("Could not find unique name for voice message file.")
                }
            })
        }
    }

    func didPressCopy(for message: NCChatMessage) {
        let pasteboard = UIPasteboard.general
        pasteboard.string = message.parsedMessage().string
        NotificationPresenter.shared().present(text: NSLocalizedString("Message copied", comment: ""), dismissAfterDelay: 5.0, includedStyle: .dark)
    }

    func didPressCopyLink(for message: NCChatMessage) {
        guard let link = room.linkURL else {
            return
        }

        let url = "\(link)#message_\(message.messageId)"
        let pasteboard = UIPasteboard.general
        pasteboard.string = url

        NotificationPresenter.shared().present(text: NSLocalizedString("Message link copied", comment: ""), dismissAfterDelay: 5.0, includedStyle: .dark)
    }

    func didPressCopySelection(for message: NCChatMessage) {
        let vc = MessageTextViewController(messageText: message.parsedMessage().string)
        self.presentWithNavigation(vc, animated: true)
    }

    func didPressTranslate(for message: NCChatMessage) {
        let translateMessageVC = MessageTranslationViewController(message: message.parsedMessage().string, availableTranslations: NCDatabaseManager.sharedInstance().availableTranslations(forAccountId: self.room.accountId))
        self.presentWithNavigation(translateMessageVC, animated: true)
    }

    func didPressTranscribeVoiceMessage(for message: NCChatMessage) {
        let downloader = NCChatFileController()
        downloader.delegate = self
        downloader.messageType = kMessageTypeVoiceMessage
        downloader.actionType = actionTypeTranscribeVoiceMessage
        downloader.downloadFile(fromMessage: message.file())
    }

    func didPressEdit(for message: NCChatMessage) {
        self.savePendingMessage()

        let warningString = NSLocalizedString("Adding a mention will only notify users that did not read the message yet", comment: "")
        let warningView = UIView()
        let warningLabel = UILabel()

        warningView.addSubview(warningLabel)
        warningLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            warningLabel.leftAnchor.constraint(equalTo: warningView.safeAreaLayoutGuide.leftAnchor, constant: 8),
            warningLabel.rightAnchor.constraint(equalTo: warningView.safeAreaLayoutGuide.rightAnchor, constant: -8),
            warningLabel.topAnchor.constraint(equalTo: warningView.safeAreaLayoutGuide.topAnchor, constant: 4),
            warningLabel.bottomAnchor.constraint(equalTo: warningView.safeAreaLayoutGuide.bottomAnchor)
        ])

        let attributedWarningString = warningString.withFont(.systemFont(ofSize: 14)).withTextColor(.secondaryLabel)

        warningLabel.attributedText = attributedWarningString
        warningLabel.numberOfLines = 0

        // Calculate the height needed to completely show the text
        let maxWidth = self.autoCompletionView.frame.width - autoCompletionView.safeAreaInsets.left - autoCompletionView.safeAreaInsets.right - 16
        let contraintRect = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let size = attributedWarningString.boundingRect(with: contraintRect, options: .usesLineFragmentOrigin, context: nil)

        // Update the frame for the new height and include the top padding
        warningView.frame = .init(x: 0, y: 0, width: size.width, height: ceil(size.height) + 4)
        self.autoCompletionView.tableHeaderView = warningView

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Show the message to edit in the reply view
            self.showReplyView(for: message)
            self.replyMessageView!.hideCloseButton()
            self.mentionsDict = message.mentionMessageParameters
            self.editingMessage = message

            // For files without a caption we start with an empty text instead of "{file}"
            if message.message == "{file}", message.file() != nil {
                self.editText("")
            } else {
                self.editText(message.parsedMessage().string)
            }
        }
    }

    func didPressDelete(for message: NCChatMessage) {
        if message.sendingFailed || message.isOfflineMessage {
            self.removePermanentlyTemporaryMessage(temporaryMessage: message)
            return
        }

        if let deletingMessage = message.copy() as? NCChatMessage {
            deletingMessage.message = NSLocalizedString("Deleting message", comment: "")
            deletingMessage.isDeleting = true
            self.updateMessage(withMessageId: deletingMessage.messageId, updatedMessage: deletingMessage)
        }

        NCAPIController.sharedInstance().deleteChatMessage(inRoom: self.room.token, withMessageId: message.messageId, for: self.account) { messageDict, error, statusCode in
            if error == nil,
               let messageDict,
               let parent = messageDict["parent"] as? [AnyHashable: Any] {

                if statusCode == 202 {
                    self.view.makeToast(NSLocalizedString("Message deleted successfully, but Matterbridge is configured and the message might already be distributed to other services", comment: ""), duration: 5, position: CSToastPositionCenter)
                } else if statusCode == 200 {
                    NotificationPresenter.shared().present(text: NSLocalizedString("Message deleted successfully", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                }

                if let deleteMessage = NCChatMessage(dictionary: parent, andAccountId: self.account.accountId) {
                    self.updateMessage(withMessageId: deleteMessage.messageId, updatedMessage: deleteMessage)
                }
            } else if error != nil {
                switch statusCode {
                case 400:
                    NotificationPresenter.shared().present(text: NSLocalizedString("Message could not be deleted because it is too old", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                case 405:
                    NotificationPresenter.shared().present(text: NSLocalizedString("Only normal chat messages can be deleted", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                default:
                    NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while deleting the message", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                }

                self.updateMessage(withMessageId: message.messageId, updatedMessage: message)
            }
        }
    }

    func didPressOpenInNextcloud(for message: NCChatMessage) {
        if let file = message.file(), let path = file.path, let link = file.link {
            NCUtils.openFileInNextcloudAppOrBrowser(path: path, withFileLink: link)
        }
    }

    // MARK: - Editing support

    private func didEndTextEditing() {
        self.autoCompletionView.tableHeaderView = nil
        self.replyMessageView?.dismiss()
        self.mentionsDict.removeAll()
        self.editingMessage = nil
        self.restorePendingMessage()
        self.stopTyping(force: true)
    }

    public override func didCancelTextEditing(_ sender: Any) {
        super.didCancelTextEditing(sender)
        self.didEndTextEditing()
    }

    public override func didCommitTextEditing(_ sender: Any) {
        super.didCommitTextEditing(sender)
        self.didEndTextEditing()
    }

    // MARK: - UITextField delegate

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == self.emojiTextField, self.interactingMessage != nil {
            self.interactingMessage = nil
            textField.resignFirstResponder()
        }

        return true
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField == self.emojiTextField, string.isSingleEmoji, let interactingMessage = self.interactingMessage {
            self.addReaction(reaction: string, to: interactingMessage)
            textField.resignFirstResponder()
        }

        return true
    }

    // MARK: - UITextViewDelegate

    public override func textViewDidChange(_ textView: UITextView) {
        self.startTyping()
    }

    // MARK: - TypingIndicator support

    func sendStartedTypingMessage(to sessionId: String) {
        // Workaround: TypingPrivacy should be checked locally, not from the remote server, use serverCapabilities for now
        // TODO: Remove workaround for federated typing indicators.
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.room.accountId)
        else { return }

        if serverCapabilities.typingPrivacy {
            return
        }

        if let signalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: self.room.accountId) {
            let mySessionId = signalingController.sessionId()
            let message = NCStartedTypingMessage(from: mySessionId, sendTo: sessionId, withPayload: [:], forRoomType: "")
            signalingController.sendCall(message)
        }
    }

    func sendStartedTypingMessageToAll() {
        // Workaround: TypingPrivacy should be checked locally, not from the remote server, use serverCapabilities for now
        // TODO: Remove workaround for federated typing indicators.
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.room.accountId),
              !serverCapabilities.typingPrivacy,
              let signalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: self.room.accountId)
        else { return }

        let participantMap = signalingController.getParticipantMap()
        let mySessionId = signalingController.sessionId()

        for (key, _) in participantMap {
            if let sessionId = key as? String {
                let message = NCStartedTypingMessage(from: mySessionId, sendTo: sessionId, withPayload: [:], forRoomType: "")
                signalingController.sendCall(message)
            }
        }
    }

    func sendStoppedTypingMessageToAll() {
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().roomTalkCapabilities(for: self.room),
              !serverCapabilities.typingPrivacy,
              let signalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: self.room.accountId)
        else { return }

        let participantMap = signalingController.getParticipantMap()
        let mySessionId = signalingController.sessionId()

        for (key, _) in participantMap {
            if let sessionId = key as? String {
                let message = NCStoppedTypingMessage(from: mySessionId, sendTo: sessionId, withPayload: [:], forRoomType: "")
                signalingController.sendCall(message)
            }
        }
    }

    func startTyping() {
        if !self.isTyping {
            self.isTyping = true

            self.sendStartedTypingMessageToAll()
            self.setTypingTimer()
        }

        self.setStopTypingTimer()
    }

    func stopTyping(force: Bool) {
        if self.isTyping || force {
            self.isTyping = false
            self.sendStoppedTypingMessageToAll()
            self.invalidateStopTypingTimer()
            self.invalidateTypingTimer()
        }
    }

    // TypingTimer is used to continously send "startedTyping" messages, while we are typing
    func setTypingTimer() {
        self.invalidateTypingTimer()
        self.typingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { [weak self] _ in
            guard let self else { return }

            if self.isTyping {
                // We're still typing, send signaling message again to all participants
                self.sendStartedTypingMessageToAll()
                self.setTypingTimer()
            } else {
                // We stopped typing, we don't send anything to the participants, we just remove our timer
                self.invalidateTypingTimer()
            }
        })
    }

    func invalidateTypingTimer() {
        self.typingTimer?.invalidate()
        self.typingTimer = nil
    }

    // StopTypingTimer is used to detect when we stop typing (locally)
    func setStopTypingTimer() {
        self.invalidateStopTypingTimer()
        self.stopTypingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false, block: { [weak self] _ in
            guard let self else { return }

            if self.isTyping {
                self.isTyping = false
                self.invalidateStopTypingTimer()
            }
        })
    }

    func invalidateStopTypingTimer() {
        self.stopTypingTimer?.invalidate()
        self.stopTypingTimer =  nil
    }

    func addTypingIndicator(withUserIdentifier userIdentifier: String, andDisplayName displayName: String) {
        DispatchQueue.main.async {
            if let view = self.textInputbar.typingView as? TypingIndicatorView {
                view.addTyping(userIdentifier: userIdentifier, displayName: displayName)
            }
        }
    }

    func removeTypingIndicator(withUserIdentifier userIdentifier: String) {
        DispatchQueue.main.async {
            if let view = self.textInputbar.typingView as? TypingIndicatorView {
                view.removeTyping(userIdentifier: userIdentifier)
            }
        }
    }

    // MARK: - ShareConfirmationViewController delegate & helper

    public func shareConfirmationViewControllerDidFail(_ viewController: ShareConfirmationViewController) {
        self.dismiss(animated: true) {
            if viewController.forwardingMessage {
                NotificationPresenter.shared().present(text: NSLocalizedString("Failed to forward message", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }
        }
    }

    public func shareConfirmationViewControllerDidFinish(_ viewController: ShareConfirmationViewController) {
        self.dismiss(animated: true) {
            if viewController.forwardingMessage {
                var userInfo: [String: String] = [:]
                userInfo["token"] = viewController.room.token
                userInfo["accountId"] = viewController.account.accountId
                NotificationCenter.default.post(name: .NCChatViewControllerForwardNotification, object: self, userInfo: userInfo)
            }
        }
    }

    public func shareConfirmationViewControllerDidCancel(_ viewController: ShareConfirmationViewController) {
        self.setChatMessage(viewController.textView.text)
        self.dismiss(animated: true)
    }

    internal func createShareConfirmationViewController() -> (shareConfirmationVC: ShareConfirmationViewController, navController: NCNavigationController)? {
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.account.accountId)
        let shareConfirmationVC = ShareConfirmationViewController(room: self.room, thread: self.thread, account: self.account, serverCapabilities: serverCapabilities!)!
        shareConfirmationVC.delegate = self
        shareConfirmationVC.isModal = true
        let navigationController = NCNavigationController(rootViewController: shareConfirmationVC)

        return (shareConfirmationVC, navigationController)
    }

    // MARK: - ShareViewController Delegate

    public func shareViewControllerDidCancel(_ viewController: ShareViewController) {
        self.dismiss(animated: true)
    }

    // MARK: - TextView paste support

    public override func didPasteMediaContent(_ userInfo: [AnyHashable: Any]) {
        guard let data = userInfo[SLKTextViewPastedItemData] as? Data,
              let image = UIImage(data: data),
              let dataTypeRaw = userInfo[SLKTextViewPastedItemMediaType] as? UInt,
              let (shareConfirmationVC, navigationController) = self.createShareConfirmationViewController()
        else { return }

        shareConfirmationVC.setChatMessage(self.textView.text)
        self.setChatMessage("")

        self.present(navigationController, animated: true) {
            if SLKPastableMediaType(rawValue: dataTypeRaw).contains(.PNG), let pngData = image.pngData() {
                // For PNG we provide the fileName, as otherwise we convert it to JPEG
                var fileName = "IMG_\(String(Date().timeIntervalSince1970 * 1000)).png"
                shareConfirmationVC.shareItemController.addItem(withImageDataAndName: pngData, withName: fileName)
            } else {
                shareConfirmationVC.shareItemController.addItem(with: image)
            }
        }
    }

    // MARK: - PHPhotoPicker Delegate

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        if results.isEmpty {
            picker.dismiss(animated: true)
            return
        }

        guard let (shareConfirmationVC, navigationController) = self.createShareConfirmationViewController() else { return }

        picker.dismiss(animated: true) {
            self.present(navigationController, animated: true) {
                for result in results {

                    result.itemProvider.loadItem(forTypeIdentifier: "public.image", options: nil) { item, error in
                        guard error == nil, let item = item as? URL else { return }

                        var fileName: String

                        if let suggestedFileName = result.itemProvider.suggestedName {
                            fileName = "\(suggestedFileName).jpg"
                        } else {
                            fileName = "IMG_\(String(Date().timeIntervalSince1970 * 1000)).jpg"
                        }

                        shareConfirmationVC.shareItemController.addItem(withURLAndName: item, withName: fileName)
                    }

                    result.itemProvider.loadItem(forTypeIdentifier: "public.movie", options: nil) { item, error in
                        guard error == nil, let item = item as? URL else { return }

                        var fileName: String

                        if let suggestedFileName = result.itemProvider.suggestedName {
                            fileName = "\(suggestedFileName).mov"
                        } else {
                            fileName = "VID_\(String(Date().timeIntervalSince1970 * 1000)).mov"
                        }

                        shareConfirmationVC.shareItemController.addItem(withURLAndName: item, withName: fileName)
                    }
                }
            }
        }
    }

    // MARK: - UIImagePickerController delegate

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        self.saveImagePickerSettings(picker)

        guard let (shareConfirmationVC, navigationController) = self.createShareConfirmationViewController(),
              let mediaType = info[.mediaType] as? String
        else { return }

        if mediaType == "public.image" {
            guard let image = info[.originalImage] as? UIImage else { return }

            self.dismiss(animated: true) {
                self.present(navigationController, animated: true) {
                    shareConfirmationVC.shareItemController.addItem(with: image)
                }
            }
        } else if mediaType == "public.movie" {
            guard let imageUrl = info[.mediaURL] as? URL else { return }

            self.dismiss(animated: true) {
                self.present(navigationController, animated: true) {
                    shareConfirmationVC.shareItemController.addItem(with: imageUrl)
                }
            }
        }
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.saveImagePickerSettings(picker)
        self.dismiss(animated: true)
    }

    public func saveImagePickerSettings(_ picker: UIImagePickerController) {
        if picker.sourceType == .camera && picker.cameraCaptureMode == .photo {
            NCUserDefaults.setPreferredCameraFlashMode(picker.cameraFlashMode.rawValue)
        }
    }

    // MARK: - UIDocumentPickerViewController Delegate

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let (shareConfirmationVC, navigationController) = self.createShareConfirmationViewController() else { return }

        self.present(navigationController, animated: true) {
            for url in urls {
                shareConfirmationVC.shareItemController.addItem(with: url)
            }
        }
    }

    // MARK: - ShareLocationViewController Delegate

    public func shareLocationViewController(_ viewController: ShareLocationViewController, didSelectLocationWithLatitude latitude: Double, longitude: Double, andName name: String) {
        let richObject = GeoLocationRichObject(latitude: latitude, longitude: longitude, name: name)

        NCAPIController.sharedInstance().shareRichObject(richObject.richObjectDictionary(), inRoom: self.room.token, for: self.account) { error in
            if let error {
                print("Error sharing rich object: \(error)")
            }
        }

        viewController.dismiss(animated: true)
    }

    // MARK: - CNContactPickerViewController Delegate

    public func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        guard let vCardData = try? CNContactVCardSerialization.data(with: [contact])
        else { return }

        var vcString = String(data: vCardData, encoding: .utf8)

        if let imageData = contact.imageData {
            let base64Image = imageData.base64EncodedString()
            let vcardImageString = "PHOTO;TYPE=JPEG;ENCODING=BASE64:\(base64Image)\n"
            vcString = vcString?.replacingOccurrences(of: "END:VCARD", with: vcardImageString + "END:VCARD")
        }

        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let folderPath = paths[0]
        let filePath = (folderPath as NSString).appendingPathComponent("contact.vcf")

        do {
            try vcString?.write(toFile: filePath, atomically: true, encoding: .utf8)
            let url = URL(fileURLWithPath: filePath)
            let contactFileName = "\(contact.identifier).vcf"

            NCAPIController.sharedInstance().uniqueNameForFileUpload(withName: contactFileName, originalName: true, for: self.account) { fileServerURL, fileServerPath, _, _ in
                if let fileServerURL, let fileServerPath {
                    self.uploadFileAtPath(localPath: url.path, withFileServerURL: fileServerURL, andFileServerPath: fileServerPath, withMetaData: nil, temporaryMessage: nil)
                } else {
                    print("Could not find unique name for contact file")
                }
            }
        } catch {
            print("Could not write contact file")
        }
    }

    // MARK: - Voice messages recording

    func showVoiceMessageRecordHint() {
        let toastPosition = CGPoint(x: self.textInputbar.center.x, y: self.textInputbar.center.y - self.textInputbar.frame.size.height)
        self.view.makeToast(NSLocalizedString("Tap and hold to record a voice message, release the button to send it.", comment: ""), duration: 3, position: toastPosition)
    }

    func showVoiceMessageRecordingView() {
        self.voiceMessageRecordingView = VoiceMessageRecordingView()

        guard let voiceMessageRecordingView = self.voiceMessageRecordingView else { return }

        voiceMessageRecordingView.translatesAutoresizingMaskIntoConstraints = false

        self.textInputbar.addSubview(voiceMessageRecordingView)
        self.textInputbar.bringSubviewToFront(voiceMessageRecordingView)

        let views = [
            "voiceMessageRecordingView": voiceMessageRecordingView
        ]

        let metrics = [
            "buttonWidth": self.rightButton.frame.size.width
        ]

        self.textInputbar.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[voiceMessageRecordingView]|", metrics: metrics, views: views))
        self.textInputbar.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[voiceMessageRecordingView(>=0)]-(buttonWidth)-|", metrics: metrics, views: views))
    }

    func hideVoiceMessageRecordingView() {
        self.voiceMessageRecordingView?.isHidden = true
    }

    // MARK: - Expanded voice message recording

    func showExpandedVoiceMessageRecordingView(offset: Int) {
        let expandedView = ExpandedVoiceMessageRecordingView(
            deleteFunc: handleDelete, sendFunc: handleSend, recordFunc: handleRecord(isRecording:), timeElapsed: offset
        )

        let hostingController = UIHostingController(rootView: expandedView)
        guard let expandedVoiceMessageRecordingView = hostingController.view else { return }

        self.expandedUIHostingController = hostingController
        self.view.addSubview(expandedVoiceMessageRecordingView)

        expandedVoiceMessageRecordingView.translatesAutoresizingMaskIntoConstraints = false

        let views = [
            "expandedVoiceMessageRecordingView": expandedVoiceMessageRecordingView
        ]

        expandedVoiceMessageRecordingView.bottomAnchor.constraint(equalTo: self.textInputbar.bottomAnchor).isActive = true
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[expandedVoiceMessageRecordingView]|", metrics: nil, views: views))
    }

    func handleDelete() {
        self.recordCancelled = true
        self.stopRecordingVoiceMessage()
        handleCollapseVoiceRecording()
    }

    func handleSend() {
        if let recorder = self.recorder, recorder.isRecording {
            self.recordCancelled = false
            self.stopRecordingVoiceMessage()
        } else {
            self.hideVoiceMessageRecordingView()
            self.shareVoiceMessage()
        }
        handleCollapseVoiceRecording()
    }

    func handleRecord(isRecording: Bool) {
        if isRecording {
            if let recorder = self.recorder, !recorder.isRecording {
                let session = AVAudioSession.sharedInstance()
                try? session.setActive(true)
                recorder.record()
                print("Recording Restarted")
            }
        } else {
            recordCancelled = true
            if let recorder = self.recorder, recorder.isRecording {
                recorder.stop()
                let session = AVAudioSession.sharedInstance()
                try? session.setActive(false)
                print("Recording Stopped")
            }
        }
    }

    func handleCollapseVoiceRecording() {
        self.isVoiceRecordingLocked = false
        self.expandedUIHostingController?.removeFromParent()
        self.expandedUIHostingController?.view.isHidden = true
        self.textInputbar.bringSubviewToFront(self.textInputbar)
    }

    func setupAudioRecorder() {
        guard let userDocumentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).last,
              let outputFileURL = NSURL.fileURL(withPathComponents: [userDocumentDirectory, "voice-message-recording.m4a"])
        else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord)

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2
        ]

        self.recorder = try? AVAudioRecorder(url: outputFileURL, settings: settings)
        self.recorder?.delegate = self
        self.recorder?.isMeteringEnabled = true
        self.recorder?.prepareToRecord()
    }

    func checkPermissionAndRecordVoiceMessage() {
        let mediaType = AVMediaType.audio
        let authStatus = AVCaptureDevice.authorizationStatus(for: mediaType)

        if authStatus == AVAuthorizationStatus.authorized {
            self.startRecordingVoiceMessage()
            return
        } else if authStatus == AVAuthorizationStatus.notDetermined {
            AVCaptureDevice.requestAccess(for: mediaType, completionHandler: { granted in
                NSLog("Microphone permission granted: %@", granted ? "YES" : "NO")
            })
            return
        }

        let alert = UIAlertController(title: NSLocalizedString("Could not access microphone", comment: ""),
                                      message: NSLocalizedString("Microphone access is not allowed. Check your settings.", comment: ""),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))

        NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
    }

    func startRecordingVoiceMessage() {
        self.setupAudioRecorder()
        self.showVoiceMessageRecordingView()
        if let recorder = self.recorder, !recorder.isRecording {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
            recorder.record()
            print("Recording started")
        }
    }

    func stopRecordingVoiceMessage() {
        self.hideVoiceMessageRecordingView()
        if let recorder = self.recorder, recorder.isRecording {
            recorder.stop()
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false)
            print("Recording Stopped")
        }
    }

    func shareVoiceMessage() {
        guard let recorder = self.recorder else { return }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())

        // Replace chars that are not allowed on the filesystem
        let notAllowedCharSet = CharacterSet(charactersIn: "\\/:%")
        var roomString = self.room.displayName.components(separatedBy: notAllowedCharSet).joined(separator: " ")

        // Replace multiple spaces with 1
        if let regex = try? NSRegularExpression(pattern: "  +") {
            roomString = regex.stringByReplacingMatches(in: roomString, range: .init(location: 0, length: roomString.count), withTemplate: " ")
        }

        var audioFileName = "Talk recording from \(dateString) (\(roomString))"

        // Trim the file name if too long
        if audioFileName.count > 146 {
            audioFileName = String(audioFileName.prefix(146))
        }

        audioFileName += ".mp3"

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let chatFileController = NCChatFileController()
        chatFileController.initDownloadDirectory(for: activeAccount)

        let tempDirectoryURL = URL(fileURLWithPath: chatFileController.tempDirectoryPath)
        let destinationFilePath = tempDirectoryURL.appendingPathComponent(audioFileName).path

        var replyToMessage: NCChatMessage?
        if let replyMessageView, replyMessageView.isVisible {
            replyToMessage = replyMessageView.message
            replyMessageView.dismiss()
        }

        if let temporaryMessage = self.createTemporaryMessage(
            message: audioFileName,
            replyTo: replyToMessage,
            messageParameters: "\(destinationFilePath)",
            silently: false,
            isVoiceMessage: true
        ) {
            let movedFileToTemporaryDirectory = chatFileController.moveFileToTemporaryDirectory(
                fromSourcePath: recorder.url.path,
                destinationPath: destinationFilePath
            )

            if !movedFileToTemporaryDirectory {
                print("Failed to move voice-message to temporary directory.")
                return
            }

            if movedFileToTemporaryDirectory, NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityChatReferenceId, for: room) {
                self.appendTemporaryMessage(temporaryMessage: temporaryMessage)
            }

            NCAPIController.sharedInstance().uniqueNameForFileUpload(withName: audioFileName, originalName: true, for: activeAccount, withCompletionBlock: { fileServerURL, fileServerPath, _, _ in
                if let fileServerURL, let fileServerPath {
                    var talkMetaData: [String: Any] = ["messageType": "voice-message"]

                    if let replyToMessageId = replyToMessage?.messageId {
                        talkMetaData["replyTo"] = replyToMessageId
                    }

                    if let thread = self.thread {
                        talkMetaData["threadId"] = thread.threadId
                    }

                    self.uploadFileAtPath(localPath: destinationFilePath, withFileServerURL: fileServerURL, andFileServerPath: fileServerPath, withMetaData: talkMetaData, temporaryMessage: temporaryMessage)
                } else {
                    NSLog("Could not find unique name for voice message file.")
                }
            })
        } else {
            print("Temporary message could not be created")
        }
    }

    func uploadFileAtPath(localPath: String, withFileServerURL fileServerURL: String, andFileServerPath fileServerPath: String, withMetaData talkMetaData: [String: Any]?, temporaryMessage: NCChatMessage?) {

        ChatFileUploader.uploadFile(localPath: localPath,
                                    fileServerURL: fileServerURL,
                                    fileServerPath: fileServerPath,
                                    talkMetaData: talkMetaData,
                                    temporaryMessage: temporaryMessage,
                                    room: self.room) { statusCode, errorMessage in
            DispatchQueue.main.async {
                switch statusCode {
                case 200:
                    NSLog("Successfully uploaded and shared voice message")
                case 401:
                    NSLog("No active account found")
                    NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Upload failed", comment: ""), withMessage: NSLocalizedString("No active account found", comment: ""))
                case 403:
                    NSLog("Failed to share voice message")
                    NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Upload failed", comment: ""), withMessage: NSLocalizedString("Failed to share recording", comment: ""))
                case 404, 409:
                    NSLog("Failed to check or create attachment folder")
                    NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Upload failed", comment: ""), withMessage: NSLocalizedString("Failed to check or create attachment folder", comment: ""))
                case 507:
                    NSLog("User storage quota exceeded")
                    NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Upload failed", comment: ""),
                                                  withMessage: NSLocalizedString("User storage quota exceeded", comment: ""))
                default:
                    NSLog("Failed upload voice message with error code \(statusCode)")
                    NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Upload failed", comment: ""), withMessage: NSLocalizedString("Unknown error occurred", comment: ""))
                }
            }
        }
    }

    // MARK: - AVAudioRecorder Delegate

    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag, recorder == self.recorder, !self.recordCancelled {
            self.shareVoiceMessage()
        }
    }

    // MARK: - Voice Messages Transcribe

    func transcribeVoiceMessage(with fileStatus: NCChatFileStatus) {
        guard let fileLocalPath = fileStatus.fileLocalPath else { return }

        DispatchQueue.main.async {
            let audioFileURL = URL(fileURLWithPath: fileLocalPath)
            let viewController = VoiceMessageTranscribeViewController(audiofileUrl: audioFileURL)
            let navController = NCNavigationController(rootViewController: viewController)
            self.present(navController, animated: true)
        }
    }

    // MARK: - Voice Message Player

    func setupVoiceMessagePlayer(with fileStatus: NCChatFileStatus) {
        guard let fileLocalPath = fileStatus.fileLocalPath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: fileLocalPath)),
              let player = try? AVAudioPlayer(data: data)
        else { return }

        self.voiceMessagesPlayer = player
        self.playerAudioFileStatus = fileStatus
        player.delegate = self
        self.playVoiceMessagePlayer()
    }

    func playVoiceMessagePlayer() {
        self.setSpeakerAudioSession()
        self.enableProximitySensor()

        self.startVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.play()
    }

    func pauseVoiceMessagePlayer() {
        self.disableProximitySensor()

        self.stopVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.pause()
        self.checkVisibleCellAudioPlayers()
    }

    func stopVoiceMessagePlayer() {
        self.disableProximitySensor()

        self.stopVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.stop()
    }

    func enableProximitySensor() {
        NotificationCenter.default.addObserver(self, selector: #selector(sensorStateChange(notification:)), name: UIDevice.proximityStateDidChangeNotification, object: nil)
        UIDevice.current.isProximityMonitoringEnabled = true
    }

    func disableProximitySensor() {
        if UIDevice.current.proximityState == false {
            // Only disable monitoring if proximity sensor state is not active.
            // If not proximity sensor state is cached as active and next time we enable monitoring
            // sensorStateChange won't be trigger until proximity sensor state changes to inactive.
            NotificationCenter.default.removeObserver(self, name: UIDevice.proximityStateDidChangeNotification, object: nil)
            UIDevice.current.isProximityMonitoringEnabled = false
        }
    }

    func setSpeakerAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(AVAudioSession.Category.playback)
        try? session.setActive(true)
    }

    func setVoiceChatAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(AVAudioSession.Category.playAndRecord, mode: AVAudioSession.Mode.voiceChat)
        try? session.setActive(true)
    }

    func sensorStateChange(notification: Notification) {
        if UIDevice.current.proximityState {
            self.setVoiceChatAudioSession()
        } else {
            self.pauseVoiceMessagePlayer()
            self.setSpeakerAudioSession()
            self.disableProximitySensor()
        }
    }

    func checkVisibleCellAudioPlayers() {
        guard let tableView = self.tableView,
              let indexPaths = tableView.indexPathsForVisibleRows,
              let playerAudioFileStatus = self.playerAudioFileStatus,
              let voiceMessagesPlayer = self.voiceMessagesPlayer
        else { return }

        for indexPath in indexPaths {
            let sectionDate = self.dateSections[indexPath.section]

            if let messages = self.messages[sectionDate] {
                let message = messages[indexPath.row]

                if message.isVoiceMessage {
                    guard let cell = tableView.cellForRow(at: indexPath) as? BaseChatTableViewCell,
                          let file = message.file()
                    else { continue }

                    if file.parameterId == playerAudioFileStatus.fileId, file.path == playerAudioFileStatus.filePath {
                        cell.audioPlayerView?.setPlayerProgress(voiceMessagesPlayer.currentTime, isPlaying: voiceMessagesPlayer.isPlaying, maximumValue: voiceMessagesPlayer.duration)
                        continue
                    }

                    cell.audioPlayerView?.resetPlayer()
                }
            }
        }
    }

    func startVoiceMessagePlayerTimer() {
        self.stopVoiceMessagePlayerTimer()
        self.playerProgressTimer = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(checkVisibleCellAudioPlayers), userInfo: nil, repeats: true)
    }

    func stopVoiceMessagePlayerTimer() {
        self.playerProgressTimer?.invalidate()
        self.playerProgressTimer = nil
    }

    // MARK: - AVAudioPlayer Delegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.stopVoiceMessagePlayerTimer()
        self.checkVisibleCellAudioPlayers()
        self.disableProximitySensor()
    }

    // MARK: - Gesture recognizer

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == self.voiceMessageLongPressGesture {
            return true
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func handleLongPressInVoiceMessageRecordButton(gestureRecognizer: UILongPressGestureRecognizer) {
        if self.rightButton.tag != sendButtonTagVoice {
            return
        }

        let point = gestureRecognizer.location(in: self.view)

        if gestureRecognizer.state == .began {
            print("Start recording audio message")

            // 'Pop' feedback (strong boom)
            AudioServicesPlaySystemSound(1520)
            self.checkPermissionAndRecordVoiceMessage()
            self.shouldLockInterfaceOrientation(lock: true)
            self.recordCancelled = false
            self.longPressStartingPoint = point
            self.cancelHintLabelInitialPositionX = voiceMessageRecordingView?.slideToCancelHintLabel?.frame.origin.x
            self.voiceRecordingLockButton.alpha = 1
        } else if gestureRecognizer.state == .ended {
            self.shouldLockInterfaceOrientation(lock: false)
            self.resetVoiceRecordingLockButton()

            if !isVoiceRecordingLocked {
                if let recordingTime = self.recorder?.currentTime {
                    // Mark record as cancelled if audio message is no longer than one second
                    self.recordCancelled = recordingTime < 1
                }
                self.stopRecordingVoiceMessage()
                print("Stop recording audio message")
            }
        } else if gestureRecognizer.state == .changed {
            guard let longPressStartingPoint,
                  let cancelHintLabelInitialPositionX,
                  let voiceMessageRecordingView,
                  let slideToCancelHintLabel = voiceMessageRecordingView.slideToCancelHintLabel
            else { return }

            let slideX = longPressStartingPoint.x - point.x
            let slideY = longPressStartingPoint.y - point.y

            // Only slide view to the left
            if slideX > 0 {
                let maxSlideX = 100.0
                var labelFrame = slideToCancelHintLabel.frame
                labelFrame = .init(x: cancelHintLabelInitialPositionX - slideX, y: labelFrame.origin.y, width: labelFrame.size.width, height: labelFrame.size.height)

                slideToCancelHintLabel.frame = labelFrame
                slideToCancelHintLabel.alpha = (maxSlideX - slideX) / 100

                // Cancel recording if slided more than maxSlideX
                if slideX > maxSlideX, !self.recordCancelled, !isVoiceRecordingLocked {
                    print("Cancel recording audio message")

                    // 'Cancelled' feedback (three sequential weak booms)
                    AudioServicesPlaySystemSound(1521)
                    self.recordCancelled = true
                    self.stopRecordingVoiceMessage()
                    self.resetVoiceRecordingLockButton()
                }
            }

            if slideY > 0 {
                let maxSlideY = 64.0
                if slideY > maxSlideY, !self.recordCancelled {
                    if !isVoiceRecordingLocked {
                        self.voiceRecordingLockButton.setImage(UIImage(systemName: "lock"), for: .normal)
                        let offset = self.voiceMessageRecordingView?.recordingTimeLabel?.getTimeCounted()
                        let intOffset = Int(offset!.magnitude)
                        showExpandedVoiceMessageRecordingView(offset: intOffset)
                        print("LOCKED")
                        isVoiceRecordingLocked = true
                    }
                }
            }
        } else if gestureRecognizer.state == .cancelled || gestureRecognizer.state == .failed {
            print("Gesture cancelled or failed -> Cancel recording audio message")
            self.shouldLockInterfaceOrientation(lock: false)
            self.recordCancelled = false
            self.resetVoiceRecordingLockButton()
            self.stopRecordingVoiceMessage()
        }
    }

    func shouldLockInterfaceOrientation(lock: Bool) {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.shouldLockInterfaceOrientation = lock
        }
    }

    func resetVoiceRecordingLockButton() {
        self.voiceRecordingLockButton.alpha = 0
        self.voiceRecordingLockButton.setImage(UIImage(systemName: "lock.open"), for: .normal)
    }

    // MARK: - UIScrollViewDelegate methods

    public override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        super.scrollViewDidEndDecelerating(scrollView)

        guard scrollView == self.tableView
        else { return }

        if self.firstUnreadMessage != nil {
            self.checkUnreadMessagesVisibility()
        }

        self.updateToolbar(animated: true)
    }

    public override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        super.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)

        guard scrollView == self.tableView
        else { return }

        if !decelerate, self.firstUnreadMessage != nil {
            self.checkUnreadMessagesVisibility()
        }

        self.updateToolbar(animated: true)
    }

    public override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView == self.tableView
        else { return }

        if self.firstUnreadMessage != nil {
            self.checkUnreadMessagesVisibility()
        }

        self.updateToolbar(animated: true)
    }

    // MARK: - UITextViewDelegate methods

    public override func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Do not allow to type while recording
        if let voiceMessageLongPressGesture,
           voiceMessageLongPressGesture.state != .possible {

            return false
        }

        return super.textView(textView, shouldChangeTextIn: range, replacementText: text)
    }

    // MARK: - Chat functions

    func prependMessages(historyMessages: [NCChatMessage], addingBlockSeparator shouldAddBlockSeparator: Bool) -> IndexPath? {
        var historyDict: [Date: [NCChatMessage]] = [:]

        self.internalAppendMessages(messages: historyMessages, inDictionary: &historyDict)

        var chatSection: Date?
        var historyMessagesForSection: [NCChatMessage]?

        // Sort history sections
        let historySections = historyDict.keys.sorted()

        // Add every section in history that can't be merged with current chat messages
        for historySection in historySections {
            historyMessagesForSection = historyDict[historySection]
            chatSection = self.getKeyForDate(date: historySection, inDictionary: self.messages)

            if chatSection == nil {
                self.messages[historySection] = historyMessagesForSection
            }
        }

        self.sortDateSections()

        if shouldAddBlockSeparator {
            // Chat block separator
            let blockSeparatorMessage = NCChatMessage()
            blockSeparatorMessage.messageId = MessageSeparatorTableViewCell.chatBlockSeparatorId
            historyMessagesForSection?.append(blockSeparatorMessage)
        }

        if let lastSection = historySections.last,
           let lastHistoryMessages = historyDict[lastSection] {

            let lastHistoryMessageIP = IndexPath(row: lastHistoryMessages.count - 1, section: historySections.count - 1)

            // Merge last section of history messages with first section in current chat
            if let chatSection,
               let chatMessages = self.messages[chatSection] {

                if var historyMessagesForSection,
                   let lastHistoryMessage = historyMessagesForSection.last,
                   let firstChatMessage = chatMessages.first {

                    firstChatMessage.isGroupMessage = self.shouldGroupMessage(newMessage: firstChatMessage, withMessage: lastHistoryMessage)
                    historyMessagesForSection.append(contentsOf: chatMessages)
                    self.messages[chatSection] = historyMessagesForSection
                }
            }

            return lastHistoryMessageIP
        }

        return nil
    }

    func insertMessages(messages: [NCChatMessage]) {
        for newMessage in messages {
            // Skip thread messages when not in a thread view controller
            // Skip non thread messages when in a normal chat view controller
            guard (self.thread == nil && !newMessage.isThreadMessage())
               || (self.thread != nil && (newMessage.isThreadMessage() || newMessage.isThreadOriginalMessage()))
            else { continue }

            let newMessageDate = Date(timeIntervalSince1970: TimeInterval(newMessage.timestamp))

            if let keyDate = self.getKeyForDate(date: newMessageDate, inDictionary: self.messages),
               var messagesForDate = self.messages[keyDate] {

                for messageIndex in messagesForDate.indices {
                    let currentMessage = messagesForDate[messageIndex]

                    if currentMessage.timestamp > newMessage.timestamp {
                        // Message inserted in between other messages
                        if messageIndex > 0 {
                            let previousMessage = messagesForDate[messageIndex - 1]
                            newMessage.isGroupMessage = self.shouldGroupMessage(newMessage: newMessage, withMessage: previousMessage)
                        }

                        currentMessage.isGroupMessage = self.shouldGroupMessage(newMessage: currentMessage, withMessage: newMessage)
                        messagesForDate.insert(newMessage, at: messageIndex)
                        break
                    } else if messageIndex == (messagesForDate.count - 1) {
                        // Message inserted at the end of a date section
                        newMessage.isGroupMessage = self.shouldGroupMessage(newMessage: newMessage, withMessage: currentMessage)
                        messagesForDate.append(newMessage)
                        break
                    }
                }

                self.messages[keyDate] = messagesForDate
            } else {
                // We don't have messages for that date in our dictionary right now, so add this message as the first one
                self.messages[newMessageDate] = [newMessage]
            }
        }

        self.sortDateSections()
    }

    func appendMessages(messages: [NCChatMessage]) {
        // Because of the inout parameter, we can't call self.sortDateSections() inside the append function
        // Therefore we wrap it in this append function
        self.internalAppendMessages(messages: messages, inDictionary: &self.messages)
        self.sortDateSections()
    }

    private func internalAppendMessages(messages: [NCChatMessage], inDictionary dictionary: inout [Date: [NCChatMessage]]) {
        for newMessage in messages {
            // Skip any update message, as that would still trigger some operations on the UITableView.
            // Processing of update messages still happens when receiving new messages, so safe to skip here
            guard !newMessage.isUpdateMessage else { continue }

            // Skip thread messages when not in a thread view controller
            // Skip non thread messages when in a normal chat view controller
            guard (self.thread == nil && !newMessage.isThreadMessage())
               || (self.thread != nil && (newMessage.isThreadMessage() || newMessage.isThreadOriginalMessage()))
            else { continue }

            let newMessageDate = Date(timeIntervalSince1970: TimeInterval(newMessage.timestamp))
            let keyDate = self.getKeyForDate(date: newMessageDate, inDictionary: dictionary)

            if let keyDate, let messagesForDate = dictionary[keyDate] {
                var messageUpdated = false

                // Check if we can update the message instead of adding a new one
                for messageIndex in messagesForDate.indices {
                    let currentMessage = messagesForDate[messageIndex]

                    if currentMessage.isSameMessage(newMessage) {
                        // The newly received message either already exists or its temporary counterpart exists -> update
                        // If the user type a command the newMessage.actorType will be "bots", then we should not group those messages
                        // even if the original message was grouped.
                        // Edited messages should not be grouped to make it clear, that the message was edited
                        newMessage.isGroupMessage = currentMessage.isGroupMessage && newMessage.actorType != "bots" && newMessage.lastEditTimestamp == 0
                        dictionary[keyDate]?[messageIndex] = newMessage
                        messageUpdated = true
                        break
                    }
                }

                if !messageUpdated, let lastMessage = messagesForDate.last {
                    newMessage.isGroupMessage = self.shouldGroupMessage(newMessage: newMessage, withMessage: lastMessage)
                    dictionary[keyDate]?.append(newMessage)
                }
            } else {
                // Section not found, create new section and add message
                dictionary[newMessageDate] = [newMessage]
            }
        }
    }

    func removeMessage(at indexPath: IndexPath) {
        guard indexPath.section < self.dateSections.count else { return }

        let sectionKey = self.dateSections[indexPath.section]
        if var messages = self.messages[sectionKey], indexPath.row < messages.count {
            if messages.count == 1 {
                // Remove section
                self.messages.removeValue(forKey: sectionKey)
                self.sortDateSections()
                self.tableView?.beginUpdates()
                self.tableView?.deleteSections([indexPath.section], with: .none)
                self.tableView?.endUpdates()
            } else {
                // Remove message
                let isLastMessage = indexPath.row == (messages.count - 1)
                messages.remove(at: indexPath.row)
                self.messages[sectionKey] = messages

                self.tableView?.beginUpdates()
                self.tableView?.deleteRows(at: [indexPath], with: .none)
                self.tableView?.endUpdates()

                if !isLastMessage {
                    // Update the message next to removed message
                    let nextMessage = messages[indexPath.row]
                    nextMessage.isGroupMessage = false

                    if indexPath.row > 0 {
                        let previousMessage = messages[indexPath.row - 1]
                        nextMessage.isGroupMessage = self.shouldGroupMessage(newMessage: nextMessage, withMessage: previousMessage)
                    }

                    self.tableView?.beginUpdates()
                    self.tableView?.reloadRows(at: [indexPath], with: .none)
                    self.tableView?.endUpdates()
                }
            }
        }
    }

    func sortDateSections() {
        self.dateSections = self.messages.keys.sorted()
    }

    // MARK: - Message grouping

    func shouldGroupMessage(newMessage: NCChatMessage, withMessage lastMessage: NCChatMessage) -> Bool {
        let sameActor = newMessage.actorId == lastMessage.actorId
        let sameType = newMessage.isSystemMessage == lastMessage.isSystemMessage
        let timeDiff = (newMessage.timestamp - lastMessage.timestamp) < kChatMessageGroupTimeDifference
        let notEdited = newMessage.lastEditTimestamp == 0

        // Try to collapse system messages if the new message is not already collapsing some messages
        // Disable swiftlint -> not supported on Realm object
        // swiftlint:disable:next empty_count
        if newMessage.isSystemMessage, lastMessage.isSystemMessage, newMessage.collapsedMessages.count == 0 {
            self.tryToGroupSystemMessage(newMessage: newMessage, withMessage: lastMessage)
        }

        return sameActor && sameType && timeDiff && notEdited
    }

    func tryToGroupSystemMessage(newMessage: NCChatMessage, withMessage lastMessage: NCChatMessage) {
        if newMessage.systemMessage == lastMessage.systemMessage {
            if newMessage.actorId == lastMessage.actorId {
                // Same action and actor
                if ["user_added", "user_removed", "moderator_promoted", "moderator_demoted"].contains(newMessage.systemMessage) {
                    self.collapseSystemMessage(newMessage, withMessage: lastMessage, withAction: newMessage.systemMessage)
                }
            } else {
                // Same action, different actor
                if ["call_joined", "call_left"].contains(newMessage.systemMessage) {
                    self.collapseSystemMessage(newMessage, withMessage: lastMessage, withAction: newMessage.systemMessage)
                }
            }
        } else if newMessage.actorId == lastMessage.actorId {
            if lastMessage.systemMessage == "call_left", newMessage.systemMessage == "call_joined" {
                self.collapseSystemMessage(newMessage, withMessage: lastMessage, withAction: "call_reconnected")
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func collapseSystemMessage(_ newMessage: NCChatMessage, withMessage lastMessage: NCChatMessage, withAction action: String) {
        var collapseByMessage = lastMessage

        if let lastCollapsedByMessage = lastMessage.collapsedBy {
            collapseByMessage = lastCollapsedByMessage
            collapseByMessage.collapsedBy = nil

            self.tryToGroupSystemMessage(newMessage: newMessage, withMessage: collapseByMessage)
            return
        }

        newMessage.collapsedBy = collapseByMessage
        newMessage.isCollapsed = true

        collapseByMessage.collapsedMessages.add(newMessage.messageId as NSNumber)
        collapseByMessage.isCollapsed = true

        var isUser0Self = false
        var isUser1Self = false

        if let userDict = collapseByMessage.messageParameters["user"] as? [String: Any] {
            isUser0Self = userDict["id"] as? String == self.account.userId && userDict["type"] as? String == "user"
        }

        if let userDict = newMessage.messageParameters["user"] as? [String: Any] {
            isUser1Self = userDict["id"] as? String == self.account.userId && userDict["type"] as? String == "user"
        }

        let isActor0Self = collapseByMessage.actorId == self.account.userId && collapseByMessage.actorType == "users"
        let isActor1Self = newMessage.actorId == self.account.userId && newMessage.actorType == "users"
        let isActor0Admin = collapseByMessage.actorId == "cli" && collapseByMessage.actorType == "guests"

        collapseByMessage.collapsedIncludesUserSelf = isUser0Self || isUser1Self
        collapseByMessage.collapsedIncludesActorSelf = isActor0Self || isActor1Self

        var collapsedMessageParameters: [String: Any] = [:]

        if let actor0Dict = collapseByMessage.messageParameters["actor"],
           let actor1Dict = newMessage.messageParameters["actor"] {

            collapsedMessageParameters["actor0"] = isActor0Self ? actor1Dict : actor0Dict
            collapsedMessageParameters["actor1"] = actor1Dict
        }

        if let user0Dict = collapseByMessage.messageParameters["user"],
           let user1Dict = newMessage.messageParameters["user"] {

            collapsedMessageParameters["user0"] = isUser0Self ? user1Dict : user0Dict
            collapsedMessageParameters["user1"] = user1Dict
        }

        collapseByMessage.setCollapsedMessageParameters(collapsedMessageParameters)

        if action == "user_added" {
            if isActor0Self {
                if collapseByMessage.collapsedMessages.count == 1 {
                    collapseByMessage.collapsedMessage = NSLocalizedString("You added {user0} and {user1}", comment: "Please put {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                } else {
                    collapseByMessage.collapsedMessage = String(format: NSLocalizedString("You added {user0} and %ld more participants", comment: "Please put {user0} and %ld placeholders in the correct position on the translated text but do not translate it"), collapseByMessage.collapsedMessages.count)
                }
            } else if isActor0Admin {
                if collapseByMessage.collapsedMessages.count == 1 {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = NSLocalizedString("An administrator added you and {user0}", comment: "Please put {user0} placeholder in the correct position on the translated text but do not translate it")
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator added {user0} and {user1}", comment: "Please put {user0} and {user1} placeholders in the correct position on the translated text but do not translate them"))
                    }
                } else {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator added you and %ld more participants", comment: "Please put %ld placeholder in the correct position on the translated text but do not translate it"), collapseByMessage.collapsedMessages.count)
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator added {user0} and %ld more participants", comment: "Please put {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    }
                }
            } else {
                if collapseByMessage.collapsedMessages.count == 1 {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} added you and {user0}", comment: "Please put {actor0} and {user0} placeholders in the correct position on the translated text but do not translate them")
                    } else {
                        collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} added {user0} and {user1}", comment: "Please put {actor0}, {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                    }
                } else {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} added you and %ld more participants", comment: "Please put {actor0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} added {user0} and %ld more participants", comment: "Please put {actor0}, {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    }
                }
            }
        } else if action == "user_removed" {
            if isActor0Self {
                if collapseByMessage.collapsedMessages.count == 1 {
                    collapseByMessage.collapsedMessage = NSLocalizedString("You removed {user0} and {user1}", comment: "Please put {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                } else {
                    collapseByMessage.collapsedMessage = String(format: NSLocalizedString("You removed {user0} and %ld more participants", comment: "Please put {user0} and %ld placeholders in the correct position on the translated text but do not translate it"), collapseByMessage.collapsedMessages.count)
                }
            } else if isActor0Admin {
                if collapseByMessage.collapsedMessages.count == 1 {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = NSLocalizedString("An administrator removed you and {user0}", comment: "Please put {user0} placeholder in the correct position on the translated text but do not translate it")
                    } else {
                        collapseByMessage.collapsedMessage = NSLocalizedString("An administrator removed {user0} and {user1}", comment: "Please put {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                    }
                } else {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator removed you and %ld more participants", comment: "Please put %ld placeholder in the correct position on the translated text but do not translate it"), collapseByMessage.collapsedMessages.count)
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator removed {user0} and %ld more participants", comment: "Please put {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    }
                }
            } else {
                if collapseByMessage.collapsedMessages.count == 1 {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} removed you and {user0}", comment: "Please put {actor0} and {user0} placeholders in the correct position on the translated text but do not translate them")
                    } else {
                        collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} removed {user0} and {user1}", comment: "Please put {actor0}, {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                    }
                } else {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} removed you and %ld more participants", comment: "Please put {actor0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} removed {user0} and %ld more participants", comment: "Please put {actor0}, {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    }
                }
            }
        } else if action == "moderator_promoted" {
            if isActor0Self {
                if collapseByMessage.collapsedMessages.count == 1 {
                    collapseByMessage.collapsedMessage = NSLocalizedString("You promoted {user0} and {user1} to moderators", comment: "Please put {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                } else {
                    collapseByMessage.collapsedMessage = String(format: NSLocalizedString("You promoted {user0} and %ld more participants to moderators", comment: "Please put {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                }
            } else if isActor0Admin {
                if collapseByMessage.collapsedMessages.count == 1 {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = NSLocalizedString("An administrator promoted you and {user0} to moderators", comment: "Please put {user0} placeholder in the correct position on the translated text but do not translate it")
                    } else {
                        collapseByMessage.collapsedMessage = NSLocalizedString("An administrator promoted {user0} and {user1} to moderators", comment: "Please put {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                    }
                } else {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator promoted you and %ld more participants to moderators", comment: "Please put %ld placeholder in the correct position on the translated text but do not translate it"), collapseByMessage.collapsedMessages.count)
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator promoted {user0} and %ld more participants to moderators", comment: "Please put {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    }
                }
            } else {
                if collapseByMessage.collapsedMessages.count == 1 {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} promoted you and {user0} to moderators", comment: "Please put {actor0} and {user0} placeholders in the correct position on the translated text but do not translate them")
                    } else {
                        collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} promoted {user0} and {user1} to moderators", comment: "Please put {actor0}, {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                    }
                } else {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} promoted you and %ld more participants to moderators", comment: "Please put {actor0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} promoted {user0} and %ld more participants to moderators", comment: "Please put {actor0}, {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    }
                }
            }

        } else if action == "moderator_demoted" {
            if isActor0Self {
                if collapseByMessage.collapsedMessages.count == 1 {
                    collapseByMessage.collapsedMessage = NSLocalizedString("You demoted {user0} and {user1} from moderators", comment: "Please put {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                } else {
                    collapseByMessage.collapsedMessage = String(format: NSLocalizedString("You demoted {user0} and %ld more participants from moderators", comment: "Please put {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                }
            } else if isActor0Admin {
                if collapseByMessage.collapsedMessages.count == 1 {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = NSLocalizedString("An administrator demoted you and {user0} from moderators", comment: "Please put {user0} placeholder in the correct position on the translated text but do not translate it")
                    } else {
                        collapseByMessage.collapsedMessage = NSLocalizedString("An administrator demoted {user0} and {user1} from moderators", comment: "Please put {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                    }
                } else {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator demoted you and %ld more participants from moderators", comment: "Please put %ld placeholder in the correct position on the translated text but do not translate it"), collapseByMessage.collapsedMessages.count)
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("An administrator demoted {user0} and %ld more participants from moderators", comment: "Please put {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    }
                }
            } else {
                if collapseByMessage.collapsedMessages.count == 1 {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} demoted you and {user0} from moderators", comment: "Please put {actor0} and {user0} placeholders in the correct position on the translated text but do not translate them")
                    } else {
                        collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} demoted {user0} and {user1} from moderators", comment: "Please put {actor0}, {user0} and {user1} placeholders in the correct position on the translated text but do not translate them")
                    }
                } else {
                    if collapseByMessage.collapsedIncludesUserSelf {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} demoted you and %ld more participants from moderators", comment: "Please put {actor0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    } else {
                        collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} demoted {user0} and %ld more participants from moderators", comment: "Please put {actor0}, {user0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                    }
                }
            }
        } else if action == "call_joined" {
            if collapseByMessage.collapsedIncludesActorSelf {
                if collapseByMessage.collapsedMessages.count == 1 {
                    collapseByMessage.collapsedMessage = NSLocalizedString("You and {actor0} joined the call", comment: "Please put {actor0} placeholder in the correct position on the translated text but do not translate it")
                } else {
                    collapseByMessage.collapsedMessage = String(format: NSLocalizedString("You and %ld more participants joined the call", comment: "Please put %ld placeholder in the correct position on the translated text but do not translate it"), collapseByMessage.collapsedMessages.count)
                }
            } else {
                if collapseByMessage.collapsedMessages.count == 1 {
                    collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} and {actor1} joined the call", comment: "Please put {actor0} and {actor1} placeholders in the correct position on the translated text but do not translate them")
                } else {
                    collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} and %ld more participants joined the call", comment: "Please put {actor0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                }
            }
        } else if action == "call_left" {
            if collapseByMessage.collapsedIncludesActorSelf {
                if collapseByMessage.collapsedMessages.count == 1 {
                    collapseByMessage.collapsedMessage = NSLocalizedString("You and {actor0} left the call", comment: "Please put {actor0} placeholder in the correct position on the translated text but do not translate it")
                } else {
                    collapseByMessage.collapsedMessage = String(format: NSLocalizedString("You and %ld more participants left the call", comment: "Please put %ld placeholder in the correct position on the translated text but do not translate it"), collapseByMessage.collapsedMessages.count)
                }
            } else {
                if collapseByMessage.collapsedMessages.count == 1 {
                    collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} and {actor1} left the call", comment: "Please put {actor0} and {actor1} placeholders in the correct position on the translated text but do not translate them")
                } else {
                    collapseByMessage.collapsedMessage = String(format: NSLocalizedString("{actor0} and %ld more participants left the call", comment: "Please put {actor0} and %ld placeholders in the correct position on the translated text but do not translate them"), collapseByMessage.collapsedMessages.count)
                }
            }
        } else if action == "call_reconnected" {
            if collapseByMessage.collapsedIncludesActorSelf {
                collapseByMessage.collapsedMessage = NSLocalizedString("You reconnected to the call", comment: "")
            } else {
                collapseByMessage.collapsedMessage = NSLocalizedString("{actor0} reconnected to the call", comment: "Please put {actor0} placeholder in the correct position on the translated text but do not translate it")
            }
        }
    }

    // MARK: - Reactions

    func addReaction(reaction: String, to message: NCChatMessage) {
        if message.reactionsArray().contains(where: { $0.reaction == reaction && $0.userReacted }) {
            // We can't add reaction twice
            return
        }

        AppStoreReviewController.recordAction(AppStoreReviewController.addReaction)

        self.setTemporaryReaction(reaction: reaction, withState: .adding, toMessage: message)

        NCDatabaseManager.sharedInstance().increaseEmojiUsage(forEmoji: reaction, forAccount: self.account.accountId)

        NCAPIController.sharedInstance().addReaction(reaction, toMessage: message.messageId, inRoom: self.room.token, for: self.account) { _, error, _ in
            if error != nil {
                NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while adding a reaction to a message", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                self.removeTemporaryReaction(reaction: reaction, forMessageId: message.messageId)
            } else {
                self.setTemporaryReaction(reaction: reaction, withState: .added, toMessage: message)
            }
        }
    }

    func removeReaction(reaction: String, from message: NCChatMessage) {
        self.setTemporaryReaction(reaction: reaction, withState: .removing, toMessage: message)

        NCAPIController.sharedInstance().removeReaction(reaction, fromMessage: message.messageId, inRoom: self.room.token, for: self.account) { _, error, _ in
            if error != nil {
                NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while removing a reaction from a message", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                self.removeTemporaryReaction(reaction: reaction, forMessageId: message.messageId)
            } else {
                self.setTemporaryReaction(reaction: reaction, withState: .removed, toMessage: message)
            }
        }
    }

    func addOrRemoveReaction(reaction: NCChatReaction, in message: NCChatMessage) {
        if message.isReactionBeingModified(reaction.reaction) {
            return
        }

        if reaction.userReacted {
            self.removeReaction(reaction: reaction.reaction, from: message)
        } else {
            self.addReaction(reaction: reaction.reaction, to: message)
        }
    }

    func removeTemporaryReaction(reaction: String, forMessageId messageId: Int) {
        DispatchQueue.main.async {
            guard let (indexPath, message) = self.indexPathAndMessage(forMessageId: messageId) else { return }

            message.removeReactionFromTemporaryReactions(reaction)

            self.tableView?.beginUpdates()
            self.tableView?.endUpdates()
            self.tableView?.reloadRows(at: [indexPath], with: .none)
        }
    }

    func setTemporaryReaction(reaction: String, withState state: NCChatReactionState, toMessage message: NCChatMessage) {
        DispatchQueue.main.async {
            let isAtBottom = self.shouldScrollOnNewMessages()

            guard let (indexPath, message) = self.indexPathAndMessage(forMessageId: message.messageId) else { return }

            message.setOrUpdateTemporaryReaction(reaction, state: state)

            CATransaction.begin()
            CATransaction.setCompletionBlock {
                DispatchQueue.main.async {
                    if !isAtBottom {
                        return
                    }

                    if let (indexPath, _) = self.getLastNonUpdateMessage() {
                        self.tableView?.scrollToRow(at: indexPath, at: .bottom, animated: true)
                    }
                }
            }

            self.tableView?.beginUpdates()
            self.tableView?.endUpdates()
            self.tableView?.reloadRows(at: [indexPath], with: .none)

            CATransaction.commit()
        }
    }

    func showReactionsSummary(of message: NCChatMessage) {
        // Actuate `Peek` feedback (weak boom)
        AudioServicesPlaySystemSound(1519)

        let reactionsVC = ReactionsSummaryView(style: .insetGrouped)
        reactionsVC.room = self.room
        self.presentWithNavigation(reactionsVC, animated: true)

        NCAPIController.sharedInstance().getReactions(nil, fromMessage: message.messageId, inRoom: self.room.token, for: self.account) { reactionsDict, error, _ in
            if error == nil,
               let reactions = reactionsDict as? [String: [[String: AnyObject]]] {

                reactionsVC.updateReactions(reactions: reactions)
            }
        }
    }

    // MARK: - DateHeaderView delegate

    func dateHeaderViewTapped(inSection section: Int) {
        guard let tableView = tableView,
              section < tableView.numberOfSections,
              tableView.numberOfRows(inSection: section) > 0 else {
            return
        }

        tableView.scrollToRow(at: IndexPath(row: 0, section: section), at: .none, animated: true)
    }

    // MARK: - UITableViewDataSource methods

    public override func numberOfSections(in tableView: UITableView) -> Int {
        if tableView != self.tableView {
            return super.numberOfSections(in: tableView)
        }

        // TODO: There should be a better place to do this
        if tableView == self.tableView, !self.dateSections.isEmpty {
            tableView.backgroundView = nil
        } else {
            tableView.backgroundView = self.chatBackgroundView
        }

        return self.dateSections.count
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView != self.tableView {
            return super.tableView(tableView, numberOfRowsInSection: section)
        }

        let dateKey = self.dateSections[section]
        return self.messages[dateKey]?.count ?? 0
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if tableView != self.tableView {
            return super.tableView(tableView, titleForHeaderInSection: section)
        }

        let date = self.dateSections[section]
        return self.getHeaderString(fromDate: date)
    }

    public override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if tableView != self.tableView {
            return super.tableView(tableView, heightForHeaderInSection: section)
        }

        let date = self.dateSections[section]

        if let messages = self.messages[date], !messages.containsVisibleMessages() {
            return 0
        }

        if let headerText = self.tableView(tableView, titleForHeaderInSection: section) {
            return DateHeaderView.height(for: headerText, fittingWidth: tableView.frame.width)
        }

        return 0
    }

    public override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView != self.tableView {
            return super.tableView(tableView, viewForHeaderInSection: section)
        }

        let headerView = DateHeaderView()
        if let headerText = self.tableView(tableView, titleForHeaderInSection: section) {
            headerView.titleLabel.text = headerText
            headerView.section = section
            headerView.delegate = self
        }

        return headerView
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        guard tableView == self.tableView else { return }

        for indexPath in indexPaths {
            guard let message = self.message(for: indexPath) else { continue }

            DispatchQueue.global(qos: .userInitiated).async {
                guard message.messageId != MessageSeparatorTableViewCell.unreadMessagesSeparatorId,
                      message.messageId != MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId,
                      message.messageId != MessageSeparatorTableViewCell.chatBlockSeparatorId
                else { return }

                if message.containsURL() {
                    message.getReferenceData()
                }
            }
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView != self.autoCompletionView,
           let message = self.message(for: indexPath) {
            return self.getCell(for: message)
        }

        return super.tableView(tableView, cellForRowAt: indexPath)
    }

    // swiftlint:disable:next cyclomatic_complexity
    func getCell(for message: NCChatMessage) -> UITableViewCell {
        if message.messageId == MessageSeparatorTableViewCell.unreadMessagesSeparatorId || message.messageId == MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId,
           let cell = self.tableView?.dequeueReusableCell(withIdentifier: MessageSeparatorTableViewCell.identifier) as? MessageSeparatorTableViewCell {

            cell.messageId = message.messageId
            cell.separatorLabel.text = MessageSeparatorTableViewCell.unreadMessagesSeparatorText
            cell.delegate = self

            if message.messageId == MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId {
                cell.setSummaryButtonVisibilty(isHidden: false)
            } else {
                cell.setSummaryButtonVisibilty(isHidden: true)
            }

            return cell
        }

        if message.messageId == MessageSeparatorTableViewCell.chatBlockSeparatorId,
           let cell = self.tableView?.dequeueReusableCell(withIdentifier: MessageSeparatorTableViewCell.identifier) as? MessageSeparatorTableViewCell {

            cell.messageId = message.messageId
            cell.separatorLabel.text = MessageSeparatorTableViewCell.chatBlockSeparatorText
            return cell
        }

        if message.isSystemMessage,
           let cell = self.tableView?.dequeueReusableCell(withIdentifier: SystemMessageCellIdentifier) as? SystemMessageTableViewCell {

            cell.delegate = self
            cell.setup(for: message)
            return cell
        }

        if message.isVoiceMessage {
            let cellIdentifier = message.isGroupMessage ? voiceGroupedMessageCellIdentifier : voiceMessageCellIdentifier

            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? BaseChatTableViewCell {
                cell.delegate = self
                cell.setup(for: message, inRoom: self.room, forThread: self.thread, withAccount: self.account)

                if let playerAudioFileStatus = self.playerAudioFileStatus,
                   let voiceMessagesPlayer = self.voiceMessagesPlayer {

                    if message.file().parameterId == playerAudioFileStatus.fileId, message.file().path == playerAudioFileStatus.filePath {
                        cell.audioPlayerView?.setPlayerProgress(voiceMessagesPlayer.currentTime, isPlaying: voiceMessagesPlayer.isPlaying, maximumValue: voiceMessagesPlayer.duration)
                    } else {
                        cell.audioPlayerView?.resetPlayer()
                    }
                } else {
                    cell.audioPlayerView?.resetPlayer()
                }

                return cell
            }
        }

        if message.file() != nil {
            let cellIdentifier = message.isGroupMessage ? fileGroupedMessageCellIdentifier : fileMessageCellIdentifier

            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? BaseChatTableViewCell {
                cell.delegate = self
                cell.setup(for: message, inRoom: self.room, forThread: self.thread, withAccount: self.account)

                return cell
            }
        }

        if message.geoLocation() != nil {
            let cellIdentifier = message.isGroupMessage ? locationGroupedMessageCellIdentifier : locationMessageCellIdentifier

            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? BaseChatTableViewCell {
                cell.delegate = self
                cell.setup(for: message, inRoom: self.room, forThread: self.thread, withAccount: self.account)

                return cell
            }
        }

        if message.poll != nil {
            let cellIdentifier = message.isGroupMessage ? pollGroupedMessageCellIdentifier : pollMessageCellIdentifier

            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? BaseChatTableViewCell {
                cell.delegate = self
                cell.setup(for: message, inRoom: self.room, forThread: self.thread, withAccount: self.account)

                return cell
            }
        }

        var cellIdentifier = chatMessageCellIdentifier

        if message.isGroupMessage {
            cellIdentifier = chatGroupedMessageCellIdentifier
        } else if message.willShowParentMessageInThread(thread) {
            cellIdentifier = chatReplyMessageCellIdentifier
        }

        if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? BaseChatTableViewCell {
            cell.delegate = self
            cell.setup(for: message, inRoom: self.room, forThread: self.thread, withAccount: self.account)

            return cell
        }

        return UITableViewCell()
    }

    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView == self.autoCompletionView {
            return super.tableView(tableView, heightForRowAt: indexPath)
        }

        if let message = self.message(for: indexPath) {
            return self.getCellHeight(for: message)
        }

        return chatMessageCellMinimumHeight
    }

    func getCellHeight(for message: NCChatMessage) -> CGFloat {
        guard let tableView = self.tableView else { return chatMessageCellMinimumHeight }

        var width = tableView.frame.width - kChatCellAvatarHeight
        width -= tableView.safeAreaInsets.left + tableView.safeAreaInsets.right

        return self.getCellHeight(for: message, with: width)
    }

    lazy var textViewForSizing: UITextView = {
        return MessageBodyTextView()
    }()

    // swiftlint:disable:next cyclomatic_complexity
    func getCellHeight(for message: NCChatMessage, with originalWidth: CGFloat) -> CGFloat {
        // Chat separators
        if message.messageId == MessageSeparatorTableViewCell.unreadMessagesSeparatorId ||
            message.messageId == MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId ||
            message.messageId == MessageSeparatorTableViewCell.chatBlockSeparatorId {

            let cell = self.getCell(for: message)
            let size = cell.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            return size.height
        }

        // Empty or collapsed system messages should not be displayed
        if message.message.isEmpty || (message.isCollapsed && message.collapsedBy != nil) {
            return 0.0
        }

        // Chat messages
        let isOwnMessage = message.isMessage(from: self.account.userId)
        let messageString = message.parsedMarkdownForChat() ?? NSMutableAttributedString()
        var width = originalWidth

        if message.isSystemMessage {
            // 4 * right(10) + dateLabel(40)
            width -= 80.0
        } else {
            // Avatar is already subtracted, but we need to take padding of left(10) into account
            width -= 10.0

            // MessageTextView has padding of 2*10
            width -= 20.0

            if isOwnMessage {
                // For own messages we have a padding of 40 to the avatar view and 10 to the right superview
                width -= 50.0
            } else {
                // For others messages, we have a padding of 10 to the avatar view und 64 to the right superview
                width -= 74.0
            }
        }

        self.textViewForSizing.attributedText = messageString

        let bodyBounds = self.textViewForSizing.sizeThatFits(CGSize(width: width, height: CGFLOAT_MAX))
        var height = ceil(bodyBounds.height)

        if message.poll != nil {
            height = PollMessageView().pollMessageBodyHeight(with: messageString.string, width: width)
        }

        if (message.isGroupMessage && !message.willShowParentMessageInThread(self.thread)) || message.isSystemMessage || isOwnMessage {
            height += 15 // MessageTextTop(10) + MessageTextBottom(5)

            if height < chatGroupedMessageCellMinimumHeight {
                height = chatGroupedMessageCellMinimumHeight
            }
        } else {
            height += 40.0 // HeaderPart(30) + MessageTextTop(5) + MessageTextBottom(5)

            if height < chatMessageCellMinimumHeight {
                height = chatMessageCellMinimumHeight
            }
        }

        // E.g. For media files we hide the filename if there's no caption, so there's no height here
        // but we always have a default height measured, so we subtract the height again
        if messageString.string.isEmpty {
            height -= ceil(bodyBounds.height)
        }

        let willShowCompleteThreadOriginalMessage = (thread == nil && message.isThreadOriginalMessage())
        if !message.reactionsArray().isEmpty || willShowCompleteThreadOriginalMessage {
            height += 40 // reactionsView(40)
            if willShowCompleteThreadOriginalMessage {
                height += 30 // SubheaderPart(30)
            }
        }

        if message.containsURL() {
            height += 105
        }

        if message.willShowParentMessageInThread(thread) {
            height += 70 // quoteView(70)
        }

        // Voice message should be before message.file check since it contains a file
        if message.isVoiceMessage {
            height -= ceil(bodyBounds.height)
            height += voiceMessageCellPlayerHeight

        } else if let file = message.file() {
            if file.previewImageHeight > 0 {
                height += CGFloat(file.previewImageHeight)
            } else if case let estimatedSize = BaseChatTableViewCell.getEstimatedPreviewSize(for: message), estimatedSize.height > 0 {
                height += estimatedSize.height
                message.setPreviewImageSize(estimatedSize)
            } else {
                height += fileMessageCellFileMaxPreviewHeight
            }

            height += 10 // right(10)
        }

        if message.geoLocation() != nil {
            height += locationMessageCellPreviewHeight + 10 // right(10)
        }

        if !message.isSystemMessage {
            // Bubble top(8) + bottom(8)
            height += 16

            // Footer height
            height += 20
        }

        return height
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == self.tableView {
            self.emojiTextField.resignFirstResponder()
            self.datePickerTextField.resignFirstResponder()

            // Disable swiftlint -> not supported on a Realm object
            // swiftlint:disable:next empty_count
            if let message = self.message(for: indexPath), message.collapsedMessages.count > 0 {
                self.cellWantsToCollapseMessages(with: message)
            }

            tableView.deselectRow(at: indexPath, animated: true)
        } else {
            super.tableView(tableView, didSelectRowAt: indexPath)
        }
    }

    // MARK: - ContextMenu (Long press on message)

    public override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if tableView == self.autoCompletionView {
            return nil
        }

        let cell = tableView.cellForRow(at: indexPath)

        if let cell = cell as? BaseChatTableViewCell {
            let pointInCell = tableView.convert(point, to: cell)
            let pointInBubbleView = cell.convert(pointInCell, to: cell.bubbleView)

            if let reactionPart = cell.reactionPart, reactionPart.frame.contains(pointInBubbleView), let message = cell.message, !message.reactionsArray().isEmpty {
                self.showReactionsSummary(of: message)
                return nil
            }
        }

        guard let message = self.message(for: indexPath) else { return nil }

        if message.isSystemMessage || message.isDeletedMessage ||
            message.messageId == MessageSeparatorTableViewCell.unreadMessagesSeparatorId ||
            message.messageId == MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId ||
            message.messageId == MessageSeparatorTableViewCell.chatBlockSeparatorId {

            return nil
        }

        var actions: [UIMenuElement] = []

        // Copy option
        actions.append(UIAction(title: NSLocalizedString("Copy", comment: ""), image: .init(systemName: "doc.on.doc")) { _ in
            self.didPressCopy(for: message)
        })

        // Copy Selection
        actions.append(UIAction(title: NSLocalizedString("Copy message selection", comment: ""), image: .init(systemName: "text.viewfinder")) { _ in
            self.didPressCopySelection(for: message)
        })

        // Copy Link
        actions.append(UIAction(title: NSLocalizedString("Copy message link", comment: ""), image: .init(systemName: "link")) { _ in
            self.didPressCopyLink(for: message)
        })

        let menu = UIMenu(children: actions)

        let configuration = UIContextMenuConfiguration(identifier: indexPath as NSIndexPath) {
            return nil
        } actionProvider: { _ in
            return menu
        }

        return configuration
    }

    public override func tableView(_ tableView: UITableView, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        animator?.addAnimations {
            // Only set these, when the context menu is fully visible
            self.contextMenuAccessoryView?.alpha = 1
            self.contextMenuMessageView?.layer.cornerRadius = 10
            self.contextMenuMessageView?.layer.mask = nil
        }
    }

    public override func tableView(_ tableView: UITableView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        animator?.addCompletion {
            // Wait until the context menu is completely hidden before we execute any method
            if let contextMenuActionBlock = self.contextMenuActionBlock {
                contextMenuActionBlock()
                self.contextMenuActionBlock = nil
            }
        }
    }

    internal func getContextMenuAccessoryView(forMessage message: NCChatMessage, forIndexPath indexPath: IndexPath, withCellHeight cellHeight: CGFloat) -> UIView? {
        // We don't provide a accessory view in the BaseChatViewController, but can add it in a subclass
        return nil
    }

    private class ContextMenuContainerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()

            if #available(iOS 26.0, *) {
                // Make our context menu accessoryView user interactive
                self.superview?.isUserInteractionEnabled = true
            }
        }
    }

    public override func tableView(_ tableView: UITableView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? NSIndexPath,
              let message = self.message(for: indexPath as IndexPath)
        else { return nil }

        let maxPreviewWidth = self.view.bounds.size.width - self.view.safeAreaInsets.left - self.view.safeAreaInsets.right
        let maxPreviewHeight = self.view.bounds.size.height * 0.4

        // TODO: Take padding into account
        let maxTextWidth = maxPreviewWidth - kChatCellAvatarHeight

        // We need to get the height of the original cell to center the preview correctly (as the preview is always non-grouped)
        let heightOfOriginalCell = self.getCellHeight(for: message, with: maxTextWidth)

        // Remember grouped-status -> Create a previewView which always is a non-grouped-message
        let isGroupMessage = message.isGroupMessage
        message.isGroupMessage = false

        let previewTableViewCell = self.getCell(for: message)
        var cellHeight = self.getCellHeight(for: message, with: maxTextWidth)

        let heightDifferenceGroupedToNonGrouped = cellHeight - heightOfOriginalCell

        // Cut the height if bigger than max height
        if cellHeight > maxPreviewHeight {
            cellHeight = maxPreviewHeight
        }

        let heightdifferenceOriginalToPreview = cellHeight - heightOfOriginalCell

        // Use the contentView of the UITableViewCell as a preview view
        let previewMessageView = previewTableViewCell.contentView
        previewMessageView.frame = CGRect(x: 0, y: 0, width: maxPreviewWidth, height: cellHeight)
        previewMessageView.layer.masksToBounds = true
        previewMessageView.backgroundColor = .clear

        // Create a mask to not show the avatar part when showing a grouped messages while animating
        // The mask will be reset in willDisplayContextMenuWithConfiguration so the avatar is visible when the context menu is shown
        if heightDifferenceGroupedToNonGrouped > 0 {
            let maskLayer = CAShapeLayer()
            let maskRect = CGRect(x: 0, y: heightDifferenceGroupedToNonGrouped + 16, width: previewMessageView.frame.size.width, height: cellHeight - 8)
            maskLayer.path = CGPath(rect: maskRect, transform: nil)

            previewMessageView.layer.mask = maskLayer
        }

        previewMessageView.backgroundColor = .systemGroupedBackground
        self.contextMenuMessageView = previewMessageView

        // Restore grouped-status
        message.isGroupMessage = isGroupMessage

        var containerView: ContextMenuContainerView
        var cellCenter = CGPoint()

        if let accessoryView = self.getContextMenuAccessoryView(forMessage: message, forIndexPath: indexPath as IndexPath, withCellHeight: cellHeight) {
            self.contextMenuAccessoryView = accessoryView

            // maxY = height + y
            let totalAccessoryFrameHeight = accessoryView.frame.maxY - cellHeight

            containerView = ContextMenuContainerView(frame: .init(x: 0, y: 0, width: Int(maxPreviewWidth), height: Int(cellHeight + totalAccessoryFrameHeight)))
            containerView.backgroundColor = .clear
            containerView.addSubview(previewMessageView)
            containerView.addSubview(accessoryView)

            if let cell = tableView.cellForRow(at: indexPath as IndexPath) {
                // On large iPhones (with regular landscape size, like iPhone X) we need to take the safe area into account when calculating the center
                let cellCenterX = cell.center.x + self.view.safeAreaInsets.left / 2 - self.view.safeAreaInsets.right / 2
                let cellCenterY = cell.center.y + totalAccessoryFrameHeight / 2 + heightdifferenceOriginalToPreview / 2 - heightDifferenceGroupedToNonGrouped
                cellCenter = CGPoint(x: cellCenterX, y: cellCenterY)
            }
        } else {
            containerView = ContextMenuContainerView(frame: .init(x: 0, y: 0, width: maxPreviewWidth, height: cellHeight))
            containerView.backgroundColor = .clear
            containerView.addSubview(previewMessageView)

            if let cell = tableView.cellForRow(at: indexPath as IndexPath) {
                // On large iPhones (with regular landscape size, like iPhone X) we need to take the safe area into account when calculating the center
                let cellCenterX = cell.center.x + self.view.safeAreaInsets.left / 2 - self.view.safeAreaInsets.right / 2
                let cellCenterY = cell.center.y + heightdifferenceOriginalToPreview / 2 - heightDifferenceGroupedToNonGrouped
                cellCenter = CGPoint(x: cellCenterX, y: cellCenterY)
            }
        }

        // Create a preview target which allows us to have a transparent background
        let previewTarget = UIPreviewTarget(container: tableView, center: cellCenter)
        let previewParameter = UIPreviewParameters()

        // Remove the background and the drop shadow from our custom preview view
        previewParameter.backgroundColor = .clear
        previewParameter.shadowPath = UIBezierPath()

        return UITargetedPreview(view: containerView, parameters: previewParameter, target: previewTarget)
    }

    // MARK: - Chat functions

    public func showLoadingHistoryView() {
        self.loadingHistoryView = UIActivityIndicatorView(frame: .init(x: 0, y: 0, width: 30, height: 30))
        self.loadingHistoryView?.color = .darkGray
        self.loadingHistoryView?.startAnimating()
        self.tableView?.tableHeaderView = self.loadingHistoryView
    }

    func hideLoadingHistoryView() {
        self.loadingHistoryView = nil
        self.tableView?.tableHeaderView = nil
    }

    func shouldScrollOnNewMessages() -> Bool {
        guard self.isVisible, let tableView = self.tableView else { return false }

        // Scroll if table view is at the bottom (or 80px up)
        let minimumOffset = (tableView.contentSize.height - tableView.frame.size.height) - 80

        if tableView.contentOffset.y >= minimumOffset {
            return true
        }

        return false
    }

    public func cleanChat() {
        self.messages = [:]
        self.dateSections = []
        self.hideNewMessagesView()
        self.tableView?.reloadData()
    }

    public func savePendingMessage() {
        if self.textInputbar.isEditing {
            // We don't want to save a message that we are editing
            return
        }

        self.room.pendingMessage = self.textView.text
        NCRoomsManager.sharedInstance().updatePendingMessage(self.room.pendingMessage, for: self.room)
    }

    public func clearPendingMessage() {
        self.room.pendingMessage = ""
        NCRoomsManager.sharedInstance().updatePendingMessage("", for: self.room)
    }

    private func getKeyForDate(date: Date, inDictionary dict: [Date: [NCChatMessage]]) -> Date? {
        let currentCalendar = NSCalendar.current
        return dict.first(where: { currentCalendar.isDate(date, inSameDayAs: $0.key) })?.key
    }

    internal func message(for indexPath: IndexPath) -> NCChatMessage? {
        let sectionDate = self.dateSections[indexPath.section]

        if let message = self.messages[sectionDate]?[indexPath.row] {
            return message
        }

        return nil
    }

    internal func indexPath(for message: NCChatMessage) -> IndexPath? {
        let messageDate = Date(timeIntervalSince1970: TimeInterval(message.timestamp))

        guard let keyDate = self.getKeyForDate(date: messageDate, inDictionary: self.messages),
              let dateSection = dateSections.firstIndex(of: keyDate),
              let messages = messages[keyDate]
        else { return nil }

        for i in messages.indices {
            let chatMessage = messages[i]

            if chatMessage.isSameMessage(message) {
                return IndexPath(row: i, section: dateSection)
            }
        }

        return nil
    }

    /// Iterate through all messages starting with the first message and returns the first message that fulfills the predicate
    private func indexPathAndMessageFromStart(with predicate: (NCChatMessage) -> Bool) -> (indexPath: IndexPath, message: NCChatMessage)? {
        for sectionIndex in dateSections.indices {
            let section = dateSections[sectionIndex]

            guard let messages = messages[section] else { continue }

            for messageIndex in messages.indices {
                let message = messages[messageIndex]

                if predicate(message) {
                    return (IndexPath(row: messageIndex, section: sectionIndex), message)
                }
            }
        }

        return nil
    }

    /// Iterate through all messages starting with the last message and returns the first message that fulfills the predicate
    private func indexPathAndMessageFromEnd(with predicate: (NCChatMessage) -> Bool) -> (indexPath: IndexPath, message: NCChatMessage)? {
        for sectionIndex in dateSections.indices.reversed() {
            let section = dateSections[sectionIndex]

            guard let messages = messages[section] else { continue }

            for messageIndex in messages.indices.reversed() {
                let message = messages[messageIndex]

                if predicate(message) {
                    return (IndexPath(row: messageIndex, section: sectionIndex), message)
                }
            }
        }

        return nil
    }

    private func indexPathsAndMessages(with predicate: (NCChatMessage) -> Bool) -> (indexPaths: [IndexPath], messages: [NCChatMessage])? {
        var predicateIndexPaths: [IndexPath] = []
        var predicateMessages: [NCChatMessage] = []

        for sectionIndex in dateSections.indices {
            let section = dateSections[sectionIndex]

            guard let messages = messages[section] else { continue }

            for messageIndex in messages.indices {
                let message = messages[messageIndex]

                if predicate(message) {
                    predicateIndexPaths.append(IndexPath(row: messageIndex, section: sectionIndex))
                    predicateMessages.append(message)
                }
            }
        }

        return (predicateIndexPaths, predicateMessages)
    }

    internal func indexPathAndMessage(forMessageId messageId: Int) -> (indexPath: IndexPath, message: NCChatMessage)? {
        return self.indexPathAndMessageFromEnd(with: { $0.messageId == messageId })
    }

    internal func indexPathAndMessage(forReferenceId referenceId: String) -> (indexPath: IndexPath, message: NCChatMessage)? {
        return self.indexPathAndMessageFromEnd(with: { $0.referenceId == referenceId })
    }

    internal func indexPathForUnreadMessageSeparator() -> IndexPath? {
        return self.indexPathAndMessageFromEnd(with: {
            $0.messageId == MessageSeparatorTableViewCell.unreadMessagesSeparatorId || $0.messageId == MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId
        })?.indexPath
    }

    internal func getThreadOriginalMessage(forThreadId threadId: Int) -> (indexPath: IndexPath, message: NCChatMessage)? {
        return self.indexPathAndMessageFromEnd(with: { $0.threadId == threadId && $0.isThreadOriginalMessage() })
    }

    internal func getLastNonUpdateMessage() -> (indexPath: IndexPath, message: NCChatMessage)? {
        return self.indexPathAndMessageFromEnd(with: { !$0.isUpdateMessage })
    }

    internal func getLastRealMessage() -> (indexPath: IndexPath, message: NCChatMessage)? {
        // Ignore temporary messages
        return self.indexPathAndMessageFromEnd(with: { $0.messageId > 0 })
    }

    internal func getFirstRealMessage() -> (indexPath: IndexPath, message: NCChatMessage)? {
        // Ignore temporary messages
        return self.indexPathAndMessageFromStart(with: { $0.messageId > 0 })
    }

    internal func indexPathForLastMessage() -> IndexPath? {
        return self.indexPathAndMessageFromEnd(with: { _ in return true })?.indexPath
    }

    internal func removeUnreadMessagesSeparator() {
        if let indexPath = self.indexPathForUnreadMessageSeparator() {
            let separatorDate = self.dateSections[indexPath.section]
            self.messages[separatorDate]?.remove(at: indexPath.row)
            self.tableView?.deleteRows(at: [indexPath], with: .fade)
        }
    }

    internal func checkUnreadMessagesVisibility() {
        DispatchQueue.main.async {
            if let firstUnreadMessage = self.firstUnreadMessage,
               let indexPath = self.indexPath(for: firstUnreadMessage) {

                if self.tableView?.indexPathsForVisibleRows?.contains(indexPath) ?? false {
                    self.hideNewMessagesView()
                }
            }
        }
    }

    internal func highlightMessage(at indexPath: IndexPath, with scrollPosition: UITableView.ScrollPosition) {
        self.tableView?.selectRow(at: indexPath, animated: true, scrollPosition: scrollPosition)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.tableView?.deselectRow(at: indexPath, animated: true)
        }
    }

    internal func highlightMessageWithContentOffset(messageId: Int) {
        guard messageId > 0,
              let tableView = self.tableView,
              let (indexPath, _) = self.indexPathAndMessage(forMessageId: messageId)
        else { return }

        self.highlightMessage(at: indexPath, with: .none)

        let rect = tableView.rectForRow(at: indexPath)

        // ContentOffset when the cell is at the top of the tableView
        let contentOffsetTop = rect.origin.y - tableView.safeAreaInsets.top

        // ContentOffset when the cell is at the middle of the tableView
        let contentOffsetMiddle = contentOffsetTop - tableView.frame.height / 2 + rect.height / 2

        // Fallback to the top offset in case the top of the cell would be scrolled outside of the view
        let newContentOffset = min(contentOffsetTop, contentOffsetMiddle)

        tableView.contentOffset.y = newContentOffset
    }

    public func reloadDataAndHighlightMessage(messageId: Int) {
        self.tableView?.reloadData()
        self.highlightMessageWithContentOffset(messageId: messageId)
    }

    func showNewMessagesView(until message: NCChatMessage) {
        self.firstUnreadMessage = message
        self.unreadMessageButton.isHidden = false
        // Check if unread messages are already visible
        self.checkUnreadMessagesVisibility()
    }

    func hideNewMessagesView() {
        self.firstUnreadMessage = nil
        self.unreadMessageButton.isHidden = true
    }

    // MARK: - FileMessageTableViewCellDelegate

    public func cellWants(toDownloadFile fileParameter: NCMessageFileParameter, for message: NCChatMessage) {
        if NCUtils.isImage(fileType: fileParameter.mimetype ?? "") {
            let mediaViewController = NCMediaViewerViewController(initialMessage: message, room: self.room)
            let navController = CustomPresentableNavigationController(rootViewController: mediaViewController)

            self.present(navController, interactiveDismissalType: .standard)

            return
        }

        let filePath = fileParameter.path ?? ""
        let fileExtension = URL(fileURLWithPath: filePath).pathExtension.lowercased()

        if NCUtils.isVideo(fileType: fileParameter.mimetype ?? "") {
            // Skip unsupported formats here ("webm" and "mkv") and use VLC later
            if !fileExtension.isEmpty, !VLCKitVideoViewController.supportedFileExtensions.contains(fileExtension) {
                let mediaViewController = NCMediaViewerViewController(initialMessage: message, room: self.room)
                let navController = CustomPresentableNavigationController(rootViewController: mediaViewController)

                self.present(navController, interactiveDismissalType: .standard)
                return
            }
        }

        if fileParameter.fileStatus != nil && fileParameter.fileStatus?.isDownloading ?? false {
            print("File already downloading -> skipping new download")
            return
        }

        let downloader = NCChatFileController()
        downloader.delegate = self
        downloader.downloadFile(fromMessage: fileParameter)
    }

    public func cellHasDownloadedImagePreview(withSize size: CGSize, for message: NCChatMessage) {
        if message.file().previewImageHeight == Int(size.height) {
            return
        }

        let isAtBottom = self.shouldScrollOnNewMessages()

        message.setPreviewImageSize(size)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            DispatchQueue.main.async {
                // make sure we're really at the bottom after updating a message since the file previews could grow in size if they contain a media file preview, thus giving the effect of not being at the bottom of the chat
                if isAtBottom, !(self.tableView?.isDecelerating ?? false) {
                    self.tableView?.slk_scrollToBottom(animated: true)
                    self.updateToolbar(animated: true)
                }
            }
        }

        self.tableView?.beginUpdates()
        self.tableView?.endUpdates()

        CATransaction.commit()
    }

    // MARK: - VoiceMessageTableViewCellDelegate

    public func cellWants(toPlayAudioFile message: NCChatMessage) {
        guard let fileParameter = message.file() else {
            print("No file for message found")
            return
        }

        if fileParameter.fileStatus != nil && fileParameter.fileStatus?.isDownloading ?? false {
            print("File already downloading -> skipping new download")
            return
        }

        if let fileStatus = fileParameter.fileStatus, fileStatus.fileLocalPath != nil && FileManager.default.fileExists(atPath: fileParameter.fileStatus?.fileLocalPath ?? "") {
            self.setupVoiceMessagePlayer(with: fileParameter.fileStatus!)
            return
        }

        if let voiceMessagesPlayer = self.voiceMessagesPlayer,
           let playerAudioFileStatus = self.playerAudioFileStatus,
           !voiceMessagesPlayer.isPlaying,
           fileParameter.parameterId == playerAudioFileStatus.fileId,
           fileParameter.path == playerAudioFileStatus.filePath {

            self.playVoiceMessagePlayer()
            return
        }

        let downloader = NCChatFileController()
        downloader.delegate = self
        downloader.messageType = kMessageTypeVoiceMessage
        downloader.downloadFile(fromMessage: fileParameter)
    }

    public func cellWants(toPauseAudioFile fileParameter: NCMessageFileParameter) {
        if let voiceMessagesPlayer = self.voiceMessagesPlayer,
           let playerAudioFileStatus = self.playerAudioFileStatus,
           voiceMessagesPlayer.isPlaying,
           fileParameter.parameterId == playerAudioFileStatus.fileId,
           fileParameter.path == playerAudioFileStatus.filePath {

            self.pauseVoiceMessagePlayer()
        }
    }

    public func cellWants(toChangeProgress progress: CGFloat, fromAudioFile fileParameter: NCMessageFileParameter) {
        if let playerAudioFileStatus = self.playerAudioFileStatus,
           fileParameter.parameterId == playerAudioFileStatus.fileId,
           fileParameter.path == playerAudioFileStatus.filePath {

            self.pauseVoiceMessagePlayer()
            self.voiceMessagesPlayer?.currentTime = progress
            self.checkVisibleCellAudioPlayers()
        }
    }

    // MARK: - LocationMessageTableViewCell

    public func cellWants(toOpenLocation geoLocationRichObject: GeoLocationRichObject) {
        self.presentWithNavigation(MapViewController(geoLocationRichObject: geoLocationRichObject), animated: true)
    }

    // MARK: - ObjectShareMessageTableViewCell

    public func cellWants(toOpenPoll poll: NCMessageParameter) {
        let pollVC = PollVotingView(room: room)
        self.presentWithNavigation(pollVC, animated: true)

        guard let pollId = Int(poll.parameterId) else { return }

        NCAPIController.sharedInstance().getPollWithId(pollId, inRoom: self.room.token, for: self.account) { poll, error, _ in
            if error == nil, let poll {
                pollVC.updatePoll(poll: poll)
            }
        }
    }

    // MARK: - Thread messages
    public func cellWants(toShowThread message: NCChatMessage) {
        self.didPressShowThread(for: message)
    }

    // MARK: - SystemMessageTableViewCellDelegate

    public func cellWantsToCollapseMessages(with message: NCChatMessage!) {
        DispatchQueue.main.async {
            guard let messageIds = message.collapsedMessages.value(forKey: "self") as? [NSNumber] else { return }

            let collapse = !message.isCollapsed
            var reloadIndexPath: [IndexPath] = []

            if let indexPath = self.indexPath(for: message) {
                reloadIndexPath.append(indexPath)
                message.isCollapsed = collapse
            }

            for messageId in messageIds {
                if let (indexPath, message) = self.indexPathAndMessage(forMessageId: messageId.intValue) {
                    reloadIndexPath.append(indexPath)
                    message.isCollapsed = collapse
                }
            }

            self.tableView?.beginUpdates()
            self.tableView?.reloadRows(at: reloadIndexPath, with: .automatic)
            self.tableView?.endUpdates()
        }
    }

    // MARK: - ChatMessageTableViewCellDelegate

    public func cellWantsToScroll(to message: NCChatMessage) {
        DispatchQueue.main.async {
            if let indexPath = self.indexPath(for: message) {
                self.highlightMessage(at: indexPath, with: .top)
            } else {
                // Show context of messages that are currently not loaded
                guard let account = self.room.account,
                      let chatViewController = ContextChatViewController(forRoom: self.room, withAccount: account, withMessage: [], withHighlightId: 0)
                else { return }

                chatViewController.showContext(ofMessageId: message.messageId, withLimit: 50, withCloseButton: true)

                let navController = NCNavigationController(rootViewController: chatViewController)
                self.present(navController, animated: true)
            }
        }
    }

    public func cellDidSelectedReaction(_ reaction: NCChatReaction!, for message: NCChatMessage) {
        // Do nothing -> override in subclass
    }

    public func cellWantsToReply(to message: NCChatMessage) {
        if self.textInputbar.isEditing {
            return
        }

        self.didPressReply(for: message)
    }

    // MARK: - MessageSeparatorTableViewCellDelegate

    func generateSummaryButtonPressed() {
        // Do nothing -> override in subclass
    }

    // MARK: - NCChatFileControllerDelegate

    public func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus) {
        if fileController.messageType == kMessageTypeVoiceMessage {
            if fileController.actionType == actionTypeTranscribeVoiceMessage {
                self.transcribeVoiceMessage(with: fileStatus)
            } else {
                self.setupVoiceMessagePlayer(with: fileStatus)
            }

            return
        }

        if self.isPreviewControllerShown {
            // We are showing a file already, no need to open another one
            return
        }

        guard let tableView = self.tableView else { return }
        var isFileCellStillVisible = false

        if let indexPathsForVisibleRows = tableView.indexPathsForVisibleRows {
            for indexPath in indexPathsForVisibleRows {
                guard let message = self.message(for: indexPath), let file = message.file() else { continue }

                if file.parameterId == fileStatus.fileId && file.path == fileStatus.filePath {
                    isFileCellStillVisible = true
                    break
                }
            }
        }

        if !isFileCellStillVisible {
            // Only open file when the corresponding cell is still visible on the screen
            return
        }

        DispatchQueue.main.async {
            self.isPreviewControllerShown = true
            self.previewControllerFilePath = fileStatus.fileLocalPath

            // When the keyboard is not dismissed, dismissing the previewController might result in a corrupted keyboardView
            self.dismissKeyboard(false)

            guard let fileLocalPath = fileStatus.fileLocalPath else { return }
            let fileExtension = URL(fileURLWithPath: fileLocalPath).pathExtension.lowercased()

            // Use VLCKitVideoViewController for file formats unsupported by the native PreviewController
            if VLCKitVideoViewController.supportedFileExtensions.contains(fileExtension) {
                let vlcKitViewController = VLCKitVideoViewController(filePath: fileLocalPath)
                vlcKitViewController.delegate = self
                vlcKitViewController.modalPresentationStyle = .fullScreen
                self.present(vlcKitViewController, animated: true)

                return
            }

            let preview = QLPreviewController()
            preview.dataSource = self
            preview.delegate = self

            NCAppBranding.styleViewController(preview)

            self.present(preview, animated: true)
        }
    }

    public func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withFileId fileId: String, withErrorDescription errorDescription: String) {
        let alert = UIAlertController(title: NSLocalizedString("Unable to load file", comment: ""),
                                      message: errorDescription,
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
    }

    // MARK: - QLPreviewControllerDelegate/DataSource

    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        if let filePath = self.previewControllerFilePath {
            return URL(fileURLWithPath: filePath) as QLPreviewItem
        }

        return URL(fileURLWithPath: "") as QLPreviewItem
    }

    public func previewControllerDidDismiss(_ controller: QLPreviewController) {
        self.isPreviewControllerShown = false
    }

    // MARK: - VLCVideoViewControllerDelegate

    func vlckitVideoViewControllerDismissed(_ controller: VLCKitVideoViewController) {
        self.isPreviewControllerShown = false
    }
}

extension Sequence where Iterator.Element == NCChatMessage {

    func containsMessage(forUserId userId: String) -> Bool {
        return self.contains(where: { !$0.isSystemMessage && $0.actorId == userId })
    }

    func containsVisibleMessages() -> Bool {
        return self.contains(where: { !$0.isUpdateMessage })
    }

}
