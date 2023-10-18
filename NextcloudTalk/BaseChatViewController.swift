//
// Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
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
import NextcloudKit
import PhotosUI
import UIKit
import Realm
import ContactsUI
import QuickLook

@objcMembers public class BaseChatViewController: InputbarViewController,
                                                  UITextFieldDelegate,
                                                  UIImagePickerControllerDelegate,
                                                  PHPickerViewControllerDelegate,
                                                  UINavigationControllerDelegate,
                                                  PollCreationViewControllerDelegate,
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
                                                  VoiceMessageTableViewCellDelegate,
                                                  FileMessageTableViewCellDelegate,
                                                  LocationMessageTableViewCellDelegate,
                                                  ObjectShareMessageTableViewCellDelegate,
                                                  ChatMessageTableViewCellDelegate {

    // MARK: - Internal var
    internal var messages: [Date: [NCChatMessage]] = [:]
    internal var dateSections: [Date] = []

    internal var isVisible = false
    internal var isTyping: Bool = false
    internal var firstUnreadMessage: NCChatMessage?

    internal var replyMessageView: ReplyMessageView?
    internal var voiceMessagesPlayer: AVAudioPlayer?
    internal var interactingMessage: NCChatMessage?
    internal var lastMessageBeforeInteraction: IndexPath?
    internal var contextMenuActionBlock: (() -> Void)?

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
        let chatBackgroundView = PlaceholderView()
        chatBackgroundView.isHidden = true
        chatBackgroundView.loadingView.startAnimating()
        chatBackgroundView.placeholderTextView.text = NSLocalizedString("No messages yet, start the conversation!", comment: "")
        chatBackgroundView.setImage(UIImage(named: "chat-placeholder"))

        self.tableView?.backgroundView = chatBackgroundView

        return chatBackgroundView
    }()

    // MARK: - Private var
    private var sendButtonTagMessage = 99
    private var sendButtonTagVoice = 98

    private var actionTypeTranscribeVoiceMessage = "transcribe-voice-message"

    private var imagePicker: UIImagePickerController?

    private var stopTypingTimer: Timer?
    private var typingTimer: Timer?
    private var voiceMessageLongPressGesture: UILongPressGestureRecognizer?
    private var recorder: AVAudioRecorder?
    private var voiceMessageRecordingView: VoiceMessageRecordingView?
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

    private lazy var inputbarBorderView: UIView = {
        let inputbarBorderView = UIView()
        inputbarBorderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inputbarBorderView.frame = .init(x: 0, y: 0, width: self.textInputbar.frame.size.width, height: 1)
        inputbarBorderView.isHidden = true
        inputbarBorderView.backgroundColor = .systemGray6

        self.textInputbar.addSubview(inputbarBorderView)

        return inputbarBorderView
    }()

    private lazy var unreadMessageButton: UIButton = {
        let unreadMessageButton = UIButton(frame: .init(x: 0, y: 0, width: 126, height: 24))

        unreadMessageButton.backgroundColor = NCAppBranding.themeColor()
        unreadMessageButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
        unreadMessageButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        unreadMessageButton.layer.cornerRadius = 12
        unreadMessageButton.clipsToBounds = true
        unreadMessageButton.isHidden = true
        unreadMessageButton.translatesAutoresizingMaskIntoConstraints = false
        unreadMessageButton.contentEdgeInsets = .init(top: 0, left: 10, bottom: 0, right: 10)
        unreadMessageButton.titleLabel?.minimumScaleFactor = 0.9
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

        button.backgroundColor = .secondarySystemBackground
        button.tintColor = .systemBlue
        button.layer.cornerRadius = button.frame.size.height / 2
        button.clipsToBounds = true
        button.alpha = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.down"), for: .normal)

        self.view.addSubview(button)

        return button
    }()

    // MARK: - Init/Deinit

    public init?(for room: NCRoom) {
        super.init(for: room, tableViewStyle: .plain)

        self.hidesBottomBarWhenPushed = true
        self.tableView?.estimatedRowHeight = 0
        self.tableView?.estimatedSectionHeaderHeight = 0

        FilePreviewImageView.setSharedImageDownloader(NCAPIController.sharedInstance().imageDownloader)
        NotificationCenter.default.addObserver(self, selector: #selector(willShowKeyboard(notification:)), name: UIWindow.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willHideKeyboard(notification:)), name: UIWindow.keyboardWillHideNotification, object: nil)

        NCUserInterfaceController.sharedInstance().numberOfAllocatedChatViewControllers += 1
    }

    public convenience init?(for room: NCRoom, withMessage messages: [NCChatMessage]) {
        self.init(for: room)

        // When we pass in a fixed number of messages, we hide the inputbar by default
        self.textInputbar.isHidden = true

        // Scroll to bottom manually after hiding the textInputbar, otherwise the
        // scrollToBottom button might be briefly visible even if not needed
        self.tableView?.slk_scrollToBottom(animated: false)

        self.appendMessages(messages: messages)
        self.tableView?.reloadData()
    }

    // Not using an optional here, because it is not available from ObjC
    public convenience init?(for room: NCRoom, withMessage messages: [NCChatMessage], withHighlightId highlightMessageId: Int) {
        self.init(for: room, withMessage: messages)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let (indexPath, _) = self.indexPathAndMessage(forMessageId: highlightMessageId) {
                self.highlightMessage(at: indexPath, with: .middle)
            }
        }
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NCUserInterfaceController.sharedInstance().numberOfAllocatedChatViewControllers -= 1
        NSLog("Dealloc BaseChatViewController")
    }

    // MARK: - View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.shouldScrollToBottomAfterKeyboardShows = false
        self.isInverted = false

        self.showSendMessageButton()
        self.leftButton.setImage(UIImage(systemName: "paperclip"), for: .normal)
        self.leftButton.accessibilityLabel = NSLocalizedString("Share a file from your Nextcloud", comment: "")
        self.leftButton.accessibilityHint = NSLocalizedString("Double tap to open file browser", comment: "")

        // Set delegate to retrieve typing events
        self.tableView?.separatorStyle = .none

        self.tableView?.register(ChatMessageTableViewCell.self, forCellReuseIdentifier: ChatMessageCellIdentifier)
        self.tableView?.register(ChatMessageTableViewCell.self, forCellReuseIdentifier: ReplyMessageCellIdentifier)
        self.tableView?.register(GroupedChatMessageTableViewCell.self, forCellReuseIdentifier: GroupedChatMessageCellIdentifier)
        self.tableView?.register(FileMessageTableViewCell.self, forCellReuseIdentifier: FileMessageCellIdentifier)
        self.tableView?.register(FileMessageTableViewCell.self, forCellReuseIdentifier: GroupedFileMessageCellIdentifier)
        self.tableView?.register(LocationMessageTableViewCell.self, forCellReuseIdentifier: LocationMessageCellIdentifier)
        self.tableView?.register(LocationMessageTableViewCell.self, forCellReuseIdentifier: GroupedLocationMessageCellIdentifier)
        self.tableView?.register(SystemMessageTableViewCell.self, forCellReuseIdentifier: SystemMessageCellIdentifier)
        self.tableView?.register(SystemMessageTableViewCell.self, forCellReuseIdentifier: InvisibleSystemMessageCellIdentifier)
        self.tableView?.register(VoiceMessageTableViewCell.self, forCellReuseIdentifier: VoiceMessageCellIdentifier)
        self.tableView?.register(VoiceMessageTableViewCell.self, forCellReuseIdentifier: GroupedVoiceMessageCellIdentifier)
        self.tableView?.register(ObjectShareMessageTableViewCell.self, forCellReuseIdentifier: ObjectShareMessageCellIdentifier)
        self.tableView?.register(ObjectShareMessageTableViewCell.self, forCellReuseIdentifier: GroupedObjectShareMessageCellIdentifier)
        self.tableView?.register(MessageSeparatorTableViewCell.self, forCellReuseIdentifier: MessageSeparatorCellIdentifier)

        let newMessagesButtonText = NSLocalizedString("↓ New messages", comment: "")

        // Need to move down to NSLayout
        let attributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12)]
        let textSize = NSString(string: newMessagesButtonText).boundingRect(with: .init(width: 300, height: 24), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        let buttonWidth = textSize.size.width + 20

        let views = [
            "unreadMessageButton": self.unreadMessageButton,
            "textInputbar": self.textInputbar,
            "scrollToBottomButton": self.scrollToBottomButton,
            "autoCompletionView": self.autoCompletionView
        ]

        let metrics = [
            "buttonWidth": buttonWidth
        ]

        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[unreadMessageButton(24)]-5-[autoCompletionView]", metrics: metrics, views: views))
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=0)-[unreadMessageButton(buttonWidth)]-(>=0)-|", metrics: metrics, views: views))

        if let view = self.view {
            self.view.addConstraint(NSLayoutConstraint(item: view, attribute: .centerX, relatedBy: .equal, toItem: self.unreadMessageButton, attribute: .centerX, multiplier: 1, constant: 0))
        }

        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:[scrollToBottomButton(44)]-10-[autoCompletionView]", metrics: metrics, views: views))
        self.view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=0)-[scrollToBottomButton(44)]-(>=0)-|", metrics: metrics, views: views))

        self.scrollToBottomButton.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10).isActive = true

        self.addMenuToLeftButton()

        self.replyMessageView?.addObserver(self, forKeyPath: "visible", options: .new, context: nil)
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
        NotificationPresenter.shared().dismiss(animated: false)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            self.updateToolbar(animated: true)
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

        if NCUtils.isValidIndexPath(lastMessageBeforeInteraction, for: tableView) {
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

    internal func createTemporaryMessage(message: String, replyTo parentMessage: NCChatMessage?, messageParameters: String, silently: Bool) -> NCChatMessage {
        let temporaryMessage = NCChatMessage()
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        temporaryMessage.accountId = activeAccount.accountId
        temporaryMessage.actorDisplayName = activeAccount.userDisplayName
        temporaryMessage.actorId = activeAccount.userId
        temporaryMessage.timestamp = Int(Date().timeIntervalSince1970)
        temporaryMessage.token = room.token
        temporaryMessage.message = self.replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: message, parameters: messageParameters)

        let referenceId = "temp-\(Date().timeIntervalSince1970 * 1000)"
        temporaryMessage.referenceId = NCUtils.sha1(from: referenceId)
        temporaryMessage.internalId = referenceId
        temporaryMessage.isTemporary = true
        temporaryMessage.parentId = parentMessage?.internalId
        temporaryMessage.messageParametersJSONString = messageParameters
        temporaryMessage.isSilent = silently
        temporaryMessage.isMarkdownMessage = NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityMarkdownMessages)

        let realm = RLMRealm.default()

        try? realm.transaction {
            realm.add(temporaryMessage)
        }

        let unmanagedTemporaryMessage = NCChatMessage(value: temporaryMessage)
        return unmanagedTemporaryMessage
    }

    internal func replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: String, parameters: String) -> String {
        var resultMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let messageParametersDict = NCMessageParameter.messageParametersDict(fromJSONString: parameters) else { return resultMessage }

        for (parameterKey, parameter) in messageParametersDict {
            let parameterKeyString = "{\(parameterKey)}"
            resultMessage = resultMessage.replacingOccurrences(of: parameter.mentionDisplayName, with: parameterKeyString)
        }

        return resultMessage
    }

    internal func replaceMessageMentionsKeysWithMentionsDisplayNames(message: String, parameters: String) -> String {
        var resultMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let messageParametersDict = NCMessageParameter.messageParametersDict(fromJSONString: parameters) else { return resultMessage }

        for (parameterKey, parameter) in messageParametersDict {
            let parameterKeyString = "{\(parameterKey)}"
            resultMessage = resultMessage.replacingOccurrences(of: parameterKeyString, with: parameter.mentionDisplayName)
        }

        return resultMessage
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

            let isAtBottom = self.shouldScrollOnNewMessages()
            let keyDate = self.dateSections[indexPath.section]
            updatedMessage.isGroupMessage = message.isGroupMessage && message.actorType != "bots"
            self.messages[keyDate]?[indexPath.row] = updatedMessage

            self.tableView?.beginUpdates()
            self.tableView?.reloadRows(at: [indexPath], with: .none)
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
        var items: [UIAction] = []

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

        // Add actions (inverted)
        items.append(ncFilesAction)
        items.append(filesAction)
        items.append(contactShareAction)

        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityLocationSharing) {
            items.append(shareLocationAction)
        }

        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityTalkPolls), self.room.type != kNCRoomTypeOneToOne {
            items.append(pollAction)
        }

        items.append(photoLibraryAction)

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            items.append(cameraAction)
        }

        self.leftButton.menu = UIMenu(children: items)
        self.leftButton.showsMenuAsPrimaryAction = true
    }

    func presentNextcloudFilesBrowser() {
        let directoryVC = DirectoryTableViewController(path: "", inRoom: self.room.token)
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

    func presentPollCreation() {
        let pollCreationVC = PollCreationViewController(style: .insetGrouped)
        pollCreationVC.pollCreationDelegate = self
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

    func didPressReply(for message: NCChatMessage) {
        // Make sure we get a smooth animation after dismissing the context menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let isAtBottom = self.shouldScrollOnNewMessages()
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

            if let replyProxyView = self.replyProxyView as? ReplyMessageView {
                self.replyMessageView = replyProxyView

                replyProxyView.presentReply(with: message, withUserId: activeAccount.userId)
                self.presentKeyboard(true)

                // Make sure we're really at the bottom after showing the replyMessageView
                if isAtBottom {
                    self.tableView?.slk_scrollToBottom(animated: false)
                    self.updateToolbar(animated: false)
                }
            }
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

        if message.isObjectShare() {
            shareViewController = ShareViewController(toForwardObjectShare: message, fromChatViewController: self)
        } else {
            shareViewController = ShareViewController(toForwardMessage: message.parsedMessage().string, fromChatViewController: self)
        }

        shareViewController.delegate = self
        self.presentWithNavigation(shareViewController, animated: true)
    }

    func didPressNoteToSelf(for message: NCChatMessage) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().getNoteToSelfRoom(for: activeAccount) { roomDict, error in
            if error == nil, let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId) {

                if message.isObjectShare() {
                    NCAPIController.sharedInstance().shareRichObject(message.richObjectFromObjectShare(), inRoom: room.token, for: activeAccount) { error in
                        if error == nil {
                            self.view.makeToast(NSLocalizedString("Added note to self", comment: ""), duration: 1.5, position: CSToastPositionCenter)
                        } else {
                            self.view.makeToast(NSLocalizedString("An error occurred while adding note", comment: ""), duration: 1.5, position: CSToastPositionCenter)
                        }
                    }
                } else {
                    NCAPIController.sharedInstance().sendChatMessage(message.parsedMessage().string, toRoom: room.token, displayName: nil, replyTo: -1, referenceId: nil, silently: false, for: activeAccount) { error in
                        if error == nil {
                            self.view.makeToast(NSLocalizedString("Added note to self", comment: ""), duration: 1.5, position: CSToastPositionCenter)
                        } else {
                            self.view.makeToast(NSLocalizedString("An error occurred while adding note", comment: ""), duration: 1.5, position: CSToastPositionCenter)
                        }
                    }
                }
            } else {
                self.view.makeToast(NSLocalizedString("An error occurred while adding note", comment: ""), duration: 1.5, position: CSToastPositionCenter)
            }
        }
    }

    func didPressResend(for message: NCChatMessage) {
        // Make sure there's no unread message separator, as the indexpath could be invalid after removing a message
        self.removeUnreadMessagesSeparator()

        self.removePermanentlyTemporaryMessage(temporaryMessage: message)
        let originalMessage = self.replaceMessageMentionsKeysWithMentionsDisplayNames(message: message.message, parameters: message.messageParametersJSONString)
        self.sendChatMessage(message: originalMessage, withParentMessage: message.parent(), messageParameters: message.messageParametersJSONString, silently: message.isSilent)
    }

    func didPressCopy(for message: NCChatMessage) {
        let pasteboard = UIPasteboard.general
        pasteboard.string = message.parsedMessage().string
        self.view.makeToast(NSLocalizedString("Message copied", comment: ""), duration: 1.5, position: CSToastPositionCenter)
    }

    func didPressTranslate(for message: NCChatMessage) {
        let translateMessageVC = MessageTranslationViewController(message: message.parsedMessage().string, availableTranslations: NCSettingsController.sharedInstance().availableTranslations())
        self.presentWithNavigation(translateMessageVC, animated: true)
    }

    func didPressTranscribeVoiceMessage(for message: NCChatMessage) {
        let downloader = NCChatFileController()
        downloader.delegate = self
        downloader.messageType = kMessageTypeVoiceMessage
        downloader.actionType = actionTypeTranscribeVoiceMessage
        downloader.downloadFile(fromMessage: message.file())
    }

    func didPressDelete(for message: NCChatMessage) {
        if message.sendingFailed, message.isOfflineMessage {
            self.removePermanentlyTemporaryMessage(temporaryMessage: message)
            return
        }

        if let deletingMessage = message.copy() as? NCChatMessage {
            deletingMessage.message = NSLocalizedString("Deleting message", comment: "")
            deletingMessage.isDeleting = true
            self.updateMessage(withMessageId: deletingMessage.messageId, updatedMessage: deletingMessage)
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().deleteChatMessage(inRoom: self.room.token, withMessageId: message.messageId, for: activeAccount) { messageDict, error, statusCode in
            if error == nil,
               let messageDict,
               let parent = messageDict["parent"] as? [AnyHashable: Any] {

                if statusCode == 202 {
                    self.view.makeToast(NSLocalizedString("Message deleted successfully, but Matterbridge is configured and the message might already be distributed to other services", comment: ""), duration: 5, position: CSToastPositionCenter)
                } else if statusCode == 200 {
                    self.view.makeToast(NSLocalizedString("Message deleted successfully", comment: ""), duration: 3, position: CSToastPositionCenter)
                }

                if let deleteMessage = NCChatMessage(dictionary: parent, andAccountId: activeAccount.accountId) {
                    self.updateMessage(withMessageId: deleteMessage.messageId, updatedMessage: deleteMessage)
                }
            } else if error != nil {
                switch statusCode {
                case 400:
                    self.view.makeToast(NSLocalizedString("Message could not be deleted because it is too old", comment: ""), duration: 5, position: CSToastPositionCenter)
                case 405:
                    self.view.makeToast(NSLocalizedString("Only normal chat messages can be deleted", comment: ""), duration: 5, position: CSToastPositionCenter)
                default:
                    self.view.makeToast(NSLocalizedString("An error occurred while deleting the message", comment: ""), duration: 5, position: CSToastPositionCenter)
                }

                self.updateMessage(withMessageId: message.messageId, updatedMessage: message)
            }
        }
    }

    func didPressOpenInNextcloud(for message: NCChatMessage) {
        if let file = message.file() {
            NCUtils.openFile(inNextcloudAppOrBrowser: file.path, withFileLink: file.link)
        }
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
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities()

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
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities()

        guard !serverCapabilities.typingPrivacy,
              let signalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: self.room.accountId),
              let participantMap = signalingController.getParticipantMap()
        else { return }

        let mySessionId = signalingController.sessionId()

        for (key, _) in participantMap {
            if let sessionId = key as? String {
                let message = NCStartedTypingMessage(from: mySessionId, sendTo: sessionId, withPayload: [:], forRoomType: "")
                signalingController.sendCall(message)
            }
        }
    }

    func sendStoppedTypingMessageToAll() {
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities()

        guard !serverCapabilities.typingPrivacy,
                let signalingController = NCSettingsController.sharedInstance().externalSignalingController(forAccountId: self.room.accountId),
              let participantMap = signalingController.getParticipantMap()
        else { return }

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

    public func shareConfirmationViewControllerDidFailed(_ viewController: ShareConfirmationViewController) {
        self.dismiss(animated: true) {
            if viewController.forwardingMessage {
                self.view.makeToast(NSLocalizedString("Failed to forward message", comment: ""), duration: 1.5, position: CSToastPositionCenter)
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

    internal func createShareConfirmationViewController() -> (shareConfirmationVC: ShareConfirmationViewController, navController: NCNavigationController) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
        let shareConfirmationVC = ShareConfirmationViewController(room: self.room, account: activeAccount, serverCapabilities: serverCapabilities)
        shareConfirmationVC.delegate = self
        shareConfirmationVC.isModal = true
        let navigationController = NCNavigationController(rootViewController: shareConfirmationVC)

        return (shareConfirmationVC, navigationController)
    }

    // MARK: - ShareViewController Delegate

    public func shareViewControllerDidCancel(_ viewController: ShareViewController) {
        self.dismiss(animated: true)
    }

    // MARK: - PHPhotoPicker Delegate

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        if results.isEmpty {
            picker.dismiss(animated: true)
            return
        }

        let (shareConfirmationVC, navigationController) = self.createShareConfirmationViewController()

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

        let (shareConfirmationVC, navigationController) = self.createShareConfirmationViewController()

        guard let mediaType = info[.mediaType] as? String else { return }

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

    // MARK: UIDocumentPickerViewController Delegate

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let (shareConfirmationVC, navigationController) = self.createShareConfirmationViewController()

        self.present(navigationController, animated: true) {
            for url in urls {
                shareConfirmationVC.shareItemController.addItem(with: url)
            }
        }
    }

    // MARK: - ShareLocationViewController Delegate

    public func shareLocationViewController(_ viewController: ShareLocationViewController, didSelectLocationWithLatitude latitude: Double, longitude: Double, andName name: String) {
        let richObject = GeoLocationRichObject(latitude: latitude, longitude: longitude, name: name)
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        NCAPIController.sharedInstance().shareRichObject(richObject.richObjectDictionary(), inRoom: self.room.token, for: activeAccount) { error in
            if let error {
                print("Error sharing rich object: \(error)")
            }
        }

        viewController.dismiss(animated: true)
    }

    // MARK: - CNContactPickerViewController Delegate

    public func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        guard let vCardData = try? CNContactVCardSerialization.data(with: [contact]) else { return }

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
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

            NCAPIController.sharedInstance().uniqueNameForFileUpload(withName: contactFileName, originalName: true, for: activeAccount) { fileServerURL, fileServerPath, _, _ in
                if let fileServerURL, let fileServerPath {
                    self.uploadFileAtPath(localPath: url.path, withFileServerURL: fileServerURL, andFileServerPath: fileServerPath, withMetaData: nil)
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
        }
    }

    func stopRecordingVoiceMessage() {
        self.hideVoiceMessageRecordingView()
        if let recorder = self.recorder, recorder.isRecording {
            recorder.stop()
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false)
        }
    }

    func shareVoiceMessage() {
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
        NCAPIController.sharedInstance().uniqueNameForFileUpload(withName: audioFileName, originalName: true, for: activeAccount, withCompletionBlock: { fileServerURL, fileServerPath, _, _ in
            if let fileServerURL, let fileServerPath, let recorder = self.recorder {
                let talkMetaData: [String: String] = ["messageType": "voice-message"]
                self.uploadFileAtPath(localPath: recorder.url.path, withFileServerURL: fileServerURL, andFileServerPath: fileServerPath, withMetaData: talkMetaData)
            } else {
                NSLog("Could not find unique name for voice message file.")
            }
        })
    }

    func uploadFileAtPath(localPath: String, withFileServerURL fileServerURL: String, andFileServerPath fileServerPath: String, withMetaData talkMetaData: [String: String]?) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().setupNCCommunication(for: activeAccount)

        NextcloudKit.shared.upload(serverUrlFileName: fileServerURL, fileNameLocalPath: localPath, taskHandler: { _ in
            NSLog("Upload task")
        }, progressHandler: { progress in
            NSLog("Progress:%f", progress.fractionCompleted)
        }, completionHandler: { _, _, _, _, _, _, _, error in
            NSLog("Upload completed with error code: %ld", error.errorCode)

            if error.errorCode == 0 {
                NCAPIController.sharedInstance().shareFileOrFolder(for: activeAccount, atPath: fileServerPath, toRoom: self.room.token, talkMetaData: talkMetaData, withCompletionBlock: { error in
                    if error != nil {
                        NSLog("Failed to share voice message")
                    }
                })
            } else if error.errorCode == 404 || error.errorCode == 409 {
                NCAPIController.sharedInstance().checkOrCreateAttachmentFolder(for: activeAccount, withCompletionBlock: { created, _ in
                    if created {
                        self.uploadFileAtPath(localPath: localPath, withFileServerURL: fileServerURL, andFileServerPath: fileServerPath, withMetaData: talkMetaData)
                    } else {
                        NSLog("Failed to check or create attachment folder")
                    }
                })
            } else {
                NSLog("Failed upload voice message")
            }
        })
    }

    // MARK: - AVAudioRecorder Delegate

    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag, recorder == self.recorder, !self.recordCancelled {
            self.shareVoiceMessage()
        }
    }

    // MARK: - Voice Messages Transcribe

    func transcribeVoiceMessage(with fileStatus: NCChatFileStatus) {
        DispatchQueue.main.async {
            let audioFileURL = URL(fileURLWithPath: fileStatus.fileLocalPath)
            let viewController = VoiceMessageTranscribeViewController(audiofileUrl: audioFileURL)
            let navController = NCNavigationController(rootViewController: viewController)
            self.present(navController, animated: true)
        }
    }

    // MARK: - Voice Message Player

    func setupVoiceMessagePlayer(with fileStatus: NCChatFileStatus) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fileStatus.fileLocalPath)),
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

                if message.isVoiceMessage() {
                    guard let cell = tableView.cellForRow(at: indexPath) as? VoiceMessageTableViewCell,
                          let file = message.file()
                    else { continue }

                    if file.parameterId == playerAudioFileStatus.fileId, file.path == playerAudioFileStatus.filePath {
                        cell.setPlayerProgress(voiceMessagesPlayer.currentTime, isPlaying: voiceMessagesPlayer.isPlaying, maximumValue: voiceMessagesPlayer.duration)
                        continue
                    }

                    cell.resetPlayer()
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
        } else if gestureRecognizer.state == .ended {
            print("Stop recording audio message")
            self.shouldLockInterfaceOrientation(lock: false)
            self.stopRecordingVoiceMessage()
        } else if gestureRecognizer.state == .changed {
            guard let longPressStartingPoint,
                  let cancelHintLabelInitialPositionX,
                  let voiceMessageRecordingView,
                  let slideToCancelHintLabel = voiceMessageRecordingView.slideToCancelHintLabel
            else { return }

            let slideX = longPressStartingPoint.x - point.x

            // Only slide view to the left
            if slideX > 0 {
                let maxSlideX = 100.0
                var labelFrame = slideToCancelHintLabel.frame
                labelFrame = .init(x: cancelHintLabelInitialPositionX - slideX, y: labelFrame.origin.y, width: labelFrame.size.width, height: labelFrame.size.height)

                slideToCancelHintLabel.frame = labelFrame
                slideToCancelHintLabel.alpha = (maxSlideX - slideX) / 100

                // Cancel recording if slided more than maxSlideX
                if slideX > maxSlideX, !self.recordCancelled {
                    print("Cancel recording audio message")

                    // 'Cancelled' feedback (three sequential weak booms)
                    AudioServicesPlaySystemSound(1521)
                    self.recordCancelled = true
                    self.stopRecordingVoiceMessage()
                }
            }
        } else if gestureRecognizer.state == .cancelled || gestureRecognizer.state == .failed {
            print("Gesture cancelled or failed -> Cancel recording audio message")
            self.shouldLockInterfaceOrientation(lock: false)
            self.recordCancelled = false
            self.stopRecordingVoiceMessage()
        }
    }

    func shouldLockInterfaceOrientation(lock: Bool) {
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.shouldLockInterfaceOrientation = lock
        }
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
            blockSeparatorMessage.messageId = kChatBlockSeparatorIdentifier
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
                        newMessage.isGroupMessage = currentMessage.isGroupMessage && newMessage.actorType != "bots"
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
                self.tableView?.reloadSections([indexPath.section], with: .none)
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
        let sameType = newMessage.isSystemMessage() == lastMessage.isSystemMessage()
        let timeDiff = (newMessage.timestamp - lastMessage.timestamp) < kChatMessageGroupTimeDifference

        // Try to collapse system messages if the new message is not already collapsing some messages
        // Disable swiftlint -> not supported on Realm object
        // swiftlint:disable:next empty_count
        if newMessage.isSystemMessage(), lastMessage.isSystemMessage(), newMessage.collapsedMessages.count == 0 {
            self.tryToGroupSystemMessage(newMessage: newMessage, withMessage: lastMessage)
        }

        return sameActor && sameType && timeDiff
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
            if ["call_joined", "call_left"].contains(newMessage.systemMessage) {
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

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        var isUser0Self = false
        var isUser1Self = false

        if let userDict = collapseByMessage.messageParameters()?["user"] as? [String: Any] {
            isUser0Self = userDict["id"] as? String == activeAccount.userId && userDict["type"] as? String == "user"
        }

        if let userDict = newMessage.messageParameters()?["user"] as? [String: Any] {
            isUser1Self = userDict["id"] as? String == activeAccount.userId && userDict["type"] as? String == "user"
        }

        let isActor0Self = collapseByMessage.actorId == activeAccount.userId && collapseByMessage.actorType == "users"
        let isActor1Self = newMessage.actorId == activeAccount.userId && newMessage.actorType == "users"
        let isActor0Admin = collapseByMessage.actorId == "cli" && collapseByMessage.actorType == "guests"

        collapseByMessage.collapsedIncludesUserSelf = isUser0Self || isUser1Self
        collapseByMessage.collapsedIncludesActorSelf = isActor0Self || isActor1Self

        var collapsedMessageParameters: [String: Any] = [:]

        if let actor0Dict = collapseByMessage.messageParameters()["actor"],
           let actor1Dict = newMessage.messageParameters()["actor"] {

            collapsedMessageParameters["actor0"] = isActor0Self ? actor1Dict : actor0Dict
            collapsedMessageParameters["actor1"] = actor1Dict
        }

        if let user0Dict = collapseByMessage.messageParameters()["user"],
           let user1Dict = newMessage.messageParameters()["user"] {

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
        if message.reactionsArray().contains(where: {$0.reaction == reaction && $0.userReacted }) {
            // We can't add reaction twice
            return
        }

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        self.setTemporaryReaction(reaction: reaction, withState: NCChatReactionStateAdding, toMessage: message)

        NCAPIController.sharedInstance().addReaction(reaction, toMessage: message.messageId, inRoom: self.room.token, for: activeAccount) { _, error, _ in
            if error != nil {
                self.view.makeToast(NSLocalizedString("An error occured while adding a reaction to a message", comment: ""), duration: 5, position: CSToastPositionCenter)
                self.removeTemporaryReaction(reaction: reaction, forMessageId: message.messageId)
            }
        }
    }

    func removeReaction(reaction: String, from message: NCChatMessage) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        self.setTemporaryReaction(reaction: reaction, withState: NCChatReactionStateRemoving, toMessage: message)

        NCAPIController.sharedInstance().removeReaction(reaction, fromMessage: message.messageId, inRoom: self.room.token, for: activeAccount) { _, error, _ in
            if error != nil {
                self.view.makeToast(NSLocalizedString("An error occured while removing a reaction from a message", comment: ""), duration: 5, position: CSToastPositionCenter)
                self.removeTemporaryReaction(reaction: reaction, forMessageId: message.messageId)
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

            message.removeReactionTemporarily(reaction)

            self.tableView?.beginUpdates()
            self.tableView?.reloadRows(at: [indexPath], with: .none)
            self.tableView?.endUpdates()
        }
    }

    func setTemporaryReaction(reaction: String, withState state: NCChatReactionState, toMessage message: NCChatMessage) {
        DispatchQueue.main.async {
            let isAtBottom = self.shouldScrollOnNewMessages()

            guard let (indexPath, message) = self.indexPathAndMessage(forMessageId: message.messageId) else { return }

            if state == NCChatReactionStateAdding {
                message.addTemporaryReaction(reaction)
            } else if state == NCChatReactionStateRemoving {
                message.removeReactionTemporarily(reaction)
            }

            self.tableView?.performBatchUpdates({
                self.tableView?.reloadRows(at: [indexPath], with: .none)
            }, completion: { _ in
                if !isAtBottom {
                    return
                }

                if let (indexPath, _) = self.getLastNonUpdateMessage() {
                    self.tableView?.scrollToRow(at: indexPath, at: .bottom, animated: true)
                }
            })

        }
    }

    func showReactionsSummary(of message: NCChatMessage) {
        // Actuate `Peek` feedback (weak boom)
        AudioServicesPlaySystemSound(1519)

        let reactionsVC = ReactionsSummaryView(style: .insetGrouped)
        self.presentWithNavigation(reactionsVC, animated: true)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getReactions(nil, fromMessage: message.messageId, inRoom: self.room.token, for: activeAccount) { reactionsDict, error, _ in
            if error == nil,
               let reactions = reactionsDict as? [String: [[String: AnyObject]]] {

                reactionsVC.updateReactions(reactions: reactions)
            }
        }
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

        return kDateHeaderViewHeight
    }

    public override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if tableView != self.tableView {
            return super.tableView(tableView, viewForHeaderInSection: section)
        }

        let headerView = DateHeaderView()
        headerView.dateLabel.text = self.tableView(tableView, titleForHeaderInSection: section)
        headerView.dateLabel.layer.cornerRadius = 12
        headerView.dateLabel.clipsToBounds = true

        if let headerLabel = headerView.dateLabel as? DateLabelCustom {
            headerLabel.tableView = tableView
        }

        return headerView
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
        if message.messageId == kUnreadMessagesSeparatorIdentifier,
           let cell = self.tableView?.dequeueReusableCell(withIdentifier: MessageSeparatorCellIdentifier) as? MessageSeparatorTableViewCell {

            cell.messageId = message.messageId
            cell.separatorLabel.text = NSLocalizedString("Unread messages", comment: "")
            return cell
        }

        if message.messageId == kChatBlockSeparatorIdentifier,
           let cell = self.tableView?.dequeueReusableCell(withIdentifier: MessageSeparatorCellIdentifier) as? MessageSeparatorTableViewCell {

            cell.messageId = message.messageId
            cell.separatorLabel.text = NSLocalizedString("Some messages not shown, will be downloaded when online", comment: "")
            return cell
        }

        if message.isUpdateMessage(),
           let cell = self.tableView?.dequeueReusableCell(withIdentifier: InvisibleSystemMessageCellIdentifier) as? SystemMessageTableViewCell {

            return cell
        }

        if message.isSystemMessage(),
           let cell = self.tableView?.dequeueReusableCell(withIdentifier: SystemMessageCellIdentifier) as? SystemMessageTableViewCell {

            cell.delegate = self
            cell.setup(for: message)
            return cell
        }

        if message.isVoiceMessage() {
            let cellIdentifier = message.isGroupMessage ? GroupedVoiceMessageCellIdentifier : VoiceMessageCellIdentifier

            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? VoiceMessageTableViewCell {
                cell.delegate = self
                cell.setup(for: message, withLastCommonReadMessage: self.room.lastCommonReadMessage)

                if let playerAudioFileStatus = self.playerAudioFileStatus,
                   let voiceMessagesPlayer = self.voiceMessagesPlayer {

                    if message.file().parameterId == playerAudioFileStatus.fileId, message.file().path == playerAudioFileStatus.filePath {
                        cell.setPlayerProgress(voiceMessagesPlayer.currentTime, isPlaying: voiceMessagesPlayer.isPlaying, maximumValue: voiceMessagesPlayer.duration)
                    } else {
                        cell.resetPlayer()
                    }
                } else {
                    cell.resetPlayer()
                }

                return cell
            }
        }

        if message.file() != nil {
            let cellIdentifier = message.isGroupMessage ? GroupedFileMessageCellIdentifier : FileMessageCellIdentifier

            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? FileMessageTableViewCell {
                cell.delegate = self
                cell.setup(for: message, withLastCommonReadMessage: self.room.lastCommonReadMessage)

                return cell
            }
        }

        if message.geoLocation() != nil {
            let cellIdentifier = message.isGroupMessage ? GroupedLocationMessageCellIdentifier : LocationMessageCellIdentifier

            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? LocationMessageTableViewCell {
                cell.delegate = self
                cell.setup(for: message, withLastCommonReadMessage: self.room.lastCommonReadMessage)

                return cell
            }
        }

        if message.poll() != nil {
            let cellIdentifier = message.isGroupMessage ? GroupedObjectShareMessageCellIdentifier : ObjectShareMessageCellIdentifier

            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: cellIdentifier) as? ObjectShareMessageTableViewCell {
                cell.delegate = self
                cell.setup(for: message, withLastCommonReadMessage: self.room.lastCommonReadMessage)

                return cell
            }
        }

        if message.parent() != nil {
            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: ReplyMessageCellIdentifier) as? ChatMessageTableViewCell {
                cell.delegate = self
                cell.setup(for: message, withLastCommonReadMessage: self.room.lastCommonReadMessage)

                return cell
            }
        }

        if message.isGroupMessage {
            if let cell = self.tableView?.dequeueReusableCell(withIdentifier: GroupedChatMessageCellIdentifier) as? GroupedChatMessageTableViewCell {
                cell.delegate = self
                cell.setup(for: message, withLastCommonReadMessage: self.room.lastCommonReadMessage)

                return cell
            }
        }

        if let cell = self.tableView?.dequeueReusableCell(withIdentifier: ChatMessageCellIdentifier) as? ChatMessageTableViewCell {
            cell.delegate = self
            cell.setup(for: message, withLastCommonReadMessage: self.room.lastCommonReadMessage)

            return cell
        }

        return UITableViewCell()
    }

    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView == self.autoCompletionView {
            return kChatMessageCellMinimumHeight
        }

        if let message = self.message(for: indexPath) {
            var width = tableView.frame.width - kChatCellAvatarHeight
            width -= tableView.safeAreaInsets.left + tableView.safeAreaInsets.right

            return self.getCellHeight(for: message, with: width)
        }

        return kChatMessageCellMinimumHeight
    }

    // swiftlint:disable:next cyclomatic_complexity
    func getCellHeight(for message: NCChatMessage, with originalWidth: CGFloat) -> CGFloat {
        // Chat separators
        if message.messageId == kUnreadMessagesSeparatorIdentifier ||
            message.messageId == kChatBlockSeparatorIdentifier {
            return kMessageSeparatorCellHeight
        }

        // Update messages (the ones that notify about an update in one message, they should not be displayed)
        if message.message.isEmpty || message.isUpdateMessage() || (message.isCollapsed && message.collapsedBy != nil) {
            return 0.0
        }

        // Chat messages
        var messageString = message.parsedMarkdownForChat() ?? NSMutableAttributedString()
        var width = originalWidth
        width -= message.isSystemMessage() ? 80.0 : 30.0 // *right(10) + dateLabel(40) : 3*right(10)

        if message.poll() != nil {
            messageString = messageString.withFont(.systemFont(ofSize: ObjectShareMessageTableViewCell.defaultFontSize()))
            width -= kObjectShareMessageCellObjectTypeImageSize + 25 // 2*right(10) + left(5)
        }

        let textStorage = NSTextStorage(attributedString: messageString)
        let targetBounding = CGRect(x: 0, y: 0, width: width, height: CGFLOAT_MAX)
        let container = NSTextContainer(size: targetBounding.size)
        container.lineFragmentPadding = 0

        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        textStorage.addLayoutManager(manager)

        manager.glyphRange(forBoundingRect: targetBounding, in: container)
        let bodyBounds = manager.usedRect(for: container)

        var height = kChatCellAvatarHeight
        height += ceil(bodyBounds.height)
        height += 20.0 // right(10) + 2*left(5)

        if height < kChatMessageCellMinimumHeight {
            height = kChatMessageCellMinimumHeight
        }

        if !message.reactionsArray().isEmpty {
            height += 40 // reactionsView(40)
        }

        if message.containsURL() {
            height += 105
        }

        if message.parent() != nil {
            height += 65 // left(5) + quoteView(60)
            return height
        }

        if message.isGroupMessage || message.isSystemMessage() {
            height = ceil(bodyBounds.height) + 10 // 2*left(5)

            if height < kGroupedChatMessageCellMinimumHeight {
                height = kGroupedChatMessageCellMinimumHeight
            }

            if !message.reactionsArray().isEmpty {
                height += 40 // reactionsView(40)
            }

            if message.containsURL() {
                height += 105
            }
        }

        // Voice message should be before message.file check since it contains a file
        if message.isVoiceMessage() {
            height -= ceil(bodyBounds.height)
            height += kVoiceMessageCellPlayerHeight + 10

            return height
        }

        if let file = message.file() {
            height += file.previewImageHeight == 0 ? kFileMessageCellFileMaxPreviewHeight : CGFloat(file.previewImageHeight)
            height += 10 // right(10)

            // if the message is a media file, reduce the message height by the bodyTextView height to hide it since it usually just contains an autogenerated file name (e.g. IMG_1234.jpg)
            if NCUtils.isImageFileType(file.mimetype) || NCUtils.isVideoFileType(file.mimetype) {
                // Only hide the filename if there's a preview available
                if file.previewAvailable {
                    height -= ceil(bodyBounds.height)
                }
            }

            return height
        }

        if message.geoLocation() != nil {
            height += kLocationMessageCellPreviewHeight + 10 // right(10)
            return height
        }

        if message.poll() != nil {
            height += 20 // 2*right(10)
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

        if let cell = tableView.cellForRow(at: indexPath) as? ChatTableViewCell {
            let pointInCell = tableView.convert(point, to: cell)
            let reactionView = cell.contentView.subviews.first(where: { $0 is ReactionsView && $0.frame.contains(pointInCell) })

            if reactionView != nil {
                self.showReactionsSummary(of: cell.message)
                return nil
            }
        }

        guard let message = self.message(for: indexPath) else { return nil }

        if message.isSystemMessage() || message.isDeletedMessage() || message.messageId == kUnreadMessagesSeparatorIdentifier {
            return nil
        }

        // Copy option
        let menu = UIMenu(children: [UIAction(title: NSLocalizedString("Copy", comment: ""), image: .init(systemName: "square.on.square")) { _ in
            self.didPressCopy(for: message)
        }])

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

    public override func tableView(_ tableView: UITableView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? NSIndexPath,
              let message = self.message(for: indexPath as IndexPath)
        else { return nil }

        let maxPreviewWidth = self.view.bounds.size.width - self.view.safeAreaInsets.left - self.view.safeAreaInsets.right
        let maxPreviewHeight = self.view.bounds.size.height * 0.6

        // TODO: Take padding into account
        let maxTextWidth = maxPreviewWidth - kChatCellAvatarHeight

        // We need to get the height of the original cell to center the preview correctly (as the preview is always non-grouped)
        let heightOfOriginalCell = self.getCellHeight(for: message, with: maxTextWidth)

        // Remember grouped-status -> Create a previewView which always is a non-grouped-message
        let isGroupMessage = message.isGroupMessage
        message.isGroupMessage = false

        let previewTableViewCell = self.getCell(for: message)
        var cellHeight = self.getCellHeight(for: message, with: maxTextWidth)

        // Cut the height if bigger than max height
        if cellHeight > maxPreviewHeight {
            cellHeight = maxPreviewHeight
        }

        // Use the contentView of the UITableViewCell as a preview view
        let previewMessageView = previewTableViewCell.contentView
        previewMessageView.frame = CGRect(x: 0, y: 0, width: maxPreviewWidth, height: cellHeight)
        previewMessageView.layer.masksToBounds = true

        // Create a mask to not show the avatar part when showing a grouped messages while animating
        // The mask will be reset in willDisplayContextMenuWithConfiguration so the avatar is visible when the context menu is shown
        let maskLayer = CAShapeLayer()
        let maskRect = CGRect(x: 0, y: previewMessageView.frame.size.height - heightOfOriginalCell, width: previewMessageView.frame.size.width, height: heightOfOriginalCell)
        maskLayer.path = CGPath(rect: maskRect, transform: nil)

        previewMessageView.layer.mask = maskLayer
        previewMessageView.backgroundColor = .systemBackground
        self.contextMenuMessageView = previewMessageView

        // Restore grouped-status
        message.isGroupMessage = isGroupMessage

        var containerView: UIView
        var cellCenter = CGPoint()

        if let accessoryView = self.getContextMenuAccessoryView(forMessage: message, forIndexPath: indexPath as IndexPath, withCellHeight: cellHeight) {
            self.contextMenuAccessoryView = accessoryView

            // maxY = height + y
            let totalAccessoryFrameHeight = accessoryView.frame.maxY - cellHeight

            containerView = UIView(frame: .init(x: 0, y: 0, width: Int(maxPreviewWidth), height: Int(cellHeight + totalAccessoryFrameHeight)))
            containerView.backgroundColor = .clear
            containerView.addSubview(previewMessageView)
            containerView.addSubview(accessoryView)

            if let cell = tableView.cellForRow(at: indexPath as IndexPath) {
                // On large iPhones (with regular landscape size, like iPhone X) we need to take the safe area into account when calculating the center
                let cellCenterX = cell.center.x + self.view.safeAreaInsets.left / 2 - self.view.safeAreaInsets.right / 2
                let cellCenterY = cell.center.y + (totalAccessoryFrameHeight) / 2 - (cellHeight - heightOfOriginalCell) / 2
                cellCenter = CGPoint(x: cellCenterX, y: cellCenterY)
            }
        } else {
            containerView = UIView(frame: .init(x: 0, y: 0, width: maxPreviewWidth, height: cellHeight))
            containerView.backgroundColor = .clear
            containerView.addSubview(previewMessageView)

            if let cell = tableView.cellForRow(at: indexPath as IndexPath) {
                // On large iPhones (with regular landscape size, like iPhone X) we need to take the safe area into account when calculating the center
                let cellCenterX = cell.center.x + self.view.safeAreaInsets.left / 2 - self.view.safeAreaInsets.right / 2
                let cellCenterY = cell.center.y - (cellHeight - heightOfOriginalCell) / 2
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

    internal func indexPathAndMessage(forMessageId messageId: Int) -> (indexPath: IndexPath, message: NCChatMessage)? {
        return self.indexPathAndMessageFromEnd(with: { $0.messageId == messageId })
    }

    internal func indexPathAndMessage(forReferenceId referenceId: String) -> (indexPath: IndexPath, message: NCChatMessage)? {
        return self.indexPathAndMessageFromEnd(with: { $0.referenceId == referenceId })
    }

    internal func indexPathForUnreadMessageSeparator() -> IndexPath? {
        return self.indexPathAndMessageFromEnd(with: { $0.messageId == kUnreadMessagesSeparatorIdentifier })?.indexPath
    }

    internal func getLastNonUpdateMessage() -> (indexPath: IndexPath, message: NCChatMessage)? {
        return self.indexPathAndMessageFromEnd(with: { !$0.isUpdateMessage() })
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

    public func cellWants(toDownloadFile fileParameter: NCMessageFileParameter!) {
        if fileParameter.fileStatus != nil && fileParameter.fileStatus?.isDownloading ?? false {
            print("File already downloading -> skipping new download")
            return
        }

        let downloader = NCChatFileController()
        downloader.delegate = self
        downloader.downloadFile(fromMessage: fileParameter)
    }

    public func cellHasDownloadedImagePreview(withHeight height: CGFloat, for message: NCChatMessage!) {
        if message.file().previewImageHeight == Int(height) {
            return
        }

        let isAtBottom = self.shouldScrollOnNewMessages()

        message.setPreviewImageHeight(height)

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

    public func cellWants(toPlayAudioFile fileParameter: NCMessageFileParameter!) {
        if fileParameter.fileStatus != nil && fileParameter.fileStatus?.isDownloading ?? false {
            print("File already downloading -> skipping new download")
            return
        }

        if let voiceMessagesPlayer = self.voiceMessagesPlayer,
           let playerAudioFileStatus = self.playerAudioFileStatus,
           voiceMessagesPlayer.isPlaying,
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

    public func cellWants(toPauseAudioFile fileParameter: NCMessageFileParameter!) {
        if let voiceMessagesPlayer = self.voiceMessagesPlayer,
           let playerAudioFileStatus = self.playerAudioFileStatus,
           voiceMessagesPlayer.isPlaying,
           fileParameter.parameterId == playerAudioFileStatus.fileId,
           fileParameter.path == playerAudioFileStatus.filePath {

            self.pauseVoiceMessagePlayer()
        }
    }

    public func cellWants(toChangeProgress progress: CGFloat, fromAudioFile fileParameter: NCMessageFileParameter!) {
        if let playerAudioFileStatus = self.playerAudioFileStatus,
           fileParameter.parameterId == playerAudioFileStatus.fileId,
           fileParameter.path == playerAudioFileStatus.filePath {

            self.pauseVoiceMessagePlayer()
            self.voiceMessagesPlayer?.currentTime = progress
            self.checkVisibleCellAudioPlayers()
        }
    }

    // MARK: - LocationMessageTableViewCell

    public func cellWants(toOpenLocation geoLocationRichObject: GeoLocationRichObject!) {
        self.presentWithNavigation(MapViewController(geoLocationRichObject: geoLocationRichObject), animated: true)
    }

    // MARK: - ObjectShareMessageTableViewCell

    public func cellWants(toOpenPoll poll: NCMessageParameter!) {
        let pollVC = PollVotingView(style: .insetGrouped)
        pollVC.room = self.room
        self.presentWithNavigation(pollVC, animated: true)

        if let pollId = Int(poll.parameterId) {
            let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
            NCAPIController.sharedInstance().getPollWithId(pollId, inRoom: self.room.token, for: activeAccount) { poll, error, _ in
                if error == nil, let poll {
                    pollVC.updatePoll(poll: poll)
                }
            }
        }
    }

    // MARK: - PollCreationViewControllerDelegate

    func pollCreationViewControllerWantsToCreatePoll(pollCreationViewController: PollCreationViewController, question: String, options: [String], resultMode: NCPollResultMode, maxVotes: Int) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().createPoll(withQuestion: question, options: options, resultMode: resultMode, maxVotes: maxVotes, inRoom: self.room.token, for: activeAccount) { _, error, _ in
            if error != nil {
                pollCreationViewController.showCreationError()
            } else {
                pollCreationViewController.close()
            }
        }
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

    public func cellWantsToScroll(to message: NCChatMessage!) {
        DispatchQueue.main.async {
            if let indexPath = self.indexPath(for: message) {
                self.highlightMessage(at: indexPath, with: .top)
            }
        }
    }

    public func cellDidSelectedReaction(_ reaction: NCChatReaction!, for message: NCChatMessage!) {
        // Do nothing -> override in subclass
    }

    public func cellWantsToReply(to message: NCChatMessage!) {
        self.didPressReply(for: message)
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

            let fileExtension = URL(fileURLWithPath: fileStatus.fileLocalPath).pathExtension.lowercased()

            // For WebM we use the VLCKitVideoViewController because the native PreviewController does not support WebM
            if fileExtension == "webm" {
                let vlcKitViewController = VLCKitVideoViewController(filePath: fileStatus.fileLocalPath)
                vlcKitViewController.delegate = self
                vlcKitViewController.modalPresentationStyle = .fullScreen
                self.present(vlcKitViewController, animated: true)

                return
            }

            let preview = QLPreviewController()
            preview.dataSource = self
            preview.delegate = self

            preview.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
            preview.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
            preview.tabBarController?.tabBar.tintColor = NCAppBranding.themeColor()

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
            appearance.backgroundColor = NCAppBranding.themeColor()
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.compactAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = appearance

            self.present(preview, animated: true)
        }
    }

    public func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withErrorDescription errorDescription: String) {
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

    func containsUserMessage() -> Bool {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        return self.contains(where: { $0.isSystemMessage() && $0.actorId == activeAccount.userId })
    }

    func containsVisibleMessages() -> Bool {
        return self.contains(where: { !$0.isUpdateMessage() })
    }

}
