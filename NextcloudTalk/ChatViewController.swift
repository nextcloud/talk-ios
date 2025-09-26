//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import NextcloudKit
import PhotosUI
import UIKit
import SwiftyAttributes
import SwiftUI

@objcMembers public class ChatViewController: BaseChatViewController {

    // MARK: - Public var
    public var presentedInCall = false
    public var presentKeyboardOnAppear = false
    public var chatController: NCChatController
    public var highlightMessageId = 0

    // MARK: - Private var
    private var hasPresentedLobby = false
    private var hasRequestedInitialHistory = false
    private var hasReceiveInitialHistory = false
    private var retrievingHistory = false

    private var hasJoinedRoom = false
    private var startReceivingMessagesAfterJoin = false
    private var offlineMode = false
    private var hasStoredHistory = true
    private var hasStopped = false
    private var hasCheckedOutOfOfficeStatus = false

    private var chatViewPresentedTimestamp = Date().timeIntervalSince1970
    private var generateSummaryFromMessageId: Int?
    private var generateSummaryTimer: Timer?

    private var startCallSilently: Bool = false

    private lazy var unreadMessagesSeparator: NCChatMessage = {
        let message = NCChatMessage()

        message.messageId = MessageSeparatorTableViewCell.unreadMessagesSeparatorId

        // We decide at this point if the unread marker should be with/without summary button, so it doesn't get changed when the room is updated
        if !self.room.isFederated, NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityChatSummary, forAccountId: self.room.accountId),
           let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.room.accountId),
           serverCapabilities.summaryThreshold <= self.room.unreadMessages {

            message.messageId = MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId
        }

        return message
    }()

    private lazy var lastReadMessage: Int = {
        return self.room.lastReadMessage
    }()

    private var lobbyCheckTimer: Timer?

    public var isThreadViewController: Bool {
        return thread != nil
    }

    // MARK: - Thread notification levels

    enum NotificationLevelOption: Int, CaseIterable {
        case room
        case allMessages
        case mentions
        case off

        var value: Int { rawValue }

        var title: String {
            switch self {
            case .room:
                return NSLocalizedString("Default", comment: "")
            case .allMessages:
                return NSLocalizedString("All messages", comment: "")
            case .mentions:
                return NSLocalizedString("@-mentions only", comment: "")
            case .off:
                return NSLocalizedString("Off", comment: "")
            }
        }

        var subtitle: String? {
            switch self {
            case .room:
                return NSLocalizedString("Follow conversation settings", comment: "")
            default:
                return nil
            }
        }

        var image: UIImage? {
            let config = UIImage.SymbolConfiguration(pointSize: 16)
            switch self {
            case .room:
                return UIImage(systemName: "bell", withConfiguration: config)
            case .allMessages:
                return UIImage(systemName: "bell.and.waves.left.and.right", withConfiguration: config)
            case .mentions:
                return UIImage(systemName: "bell", withConfiguration: config)
            case .off:
                return UIImage(systemName: "bell.slash", withConfiguration: config)
            }
        }
    }

    // MARK: - Buttons in NavigationBar

    func getCallOptionsBarButton() -> BarButtonItemWithActivity {
        let button = BarButtonItemWithActivity(image: UIImage())
        configureCallButtonAsInCall(button: button, inCall: room.hasCall)
        setupCallOptionsBarButtonMenu(button: button)

        return button
    }

    func configureCallButtonAsInCall(button: BarButtonItemWithActivity, inCall: Bool) {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16)
        let imageName = inCall ? "phone.fill" : "phone"
        let image = UIImage(systemName: imageName, withConfiguration: symbolConfiguration) ?? UIImage()
        button.setImage(image)

        let callButtonColor: UIColor = inCall ? .systemGreen : .clear

        if #available(iOS 26.0, *) {
            button.tintColor = callButtonColor
            button.style = inCall ? .prominent : .plain
        } else {
            button.setBackgroundColor(callButtonColor)
        }
    }

    func setupCallOptionsBarButtonMenu(button: BarButtonItemWithActivity) {
        let audioCallAction = UIAction(title: NSLocalizedString("Start call", comment: ""),
                                       subtitle: NSLocalizedString("Only audio and screen shares", comment: ""),
                                       image: UIImage(systemName: "phone")) { [unowned self] _ in
            startCall(withVideo: false, silently: startCallSilently, button: button)
        }

        audioCallAction.accessibilityIdentifier = "Voice only call"
        audioCallAction.accessibilityHint = NSLocalizedString("Double tap to start a voice only call", comment: "")

        let videoCallAction = UIAction(title: NSLocalizedString("Start video call", comment: ""),
                                       subtitle: NSLocalizedString("Audio, video and screen shares", comment: ""),
                                       image: UIImage(systemName: "video")) { [unowned self] _ in
            startCall(withVideo: true, silently: startCallSilently, button: button)
        }

        videoCallAction.accessibilityIdentifier = "Video call"
        videoCallAction.accessibilityHint = NSLocalizedString("Double tap to start a video call", comment: "")

        if self.room.hasCall {
            audioCallAction.title = NSLocalizedString("Join call", comment: "")
            videoCallAction.title = NSLocalizedString("Join video call", comment: "")
        } else if self.startCallSilently {
            audioCallAction.title = NSLocalizedString("Start call silently", comment: "")
            videoCallAction.title = NSLocalizedString("Start video call silently", comment: "")
        }

        var callOptions: [UIMenuElement] = [audioCallAction, videoCallAction]

        // Only show silent call option when starting a call (not when joining)
        if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilitySilentCall, for: self.room), !room.hasCall {
            var silentImage = UIImage(systemName: "bell.slash")

            if startCallSilently {
                silentImage =  UIImage(systemName: "bell.slash.fill")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            }

            let silentCallAction = UIAction(title: NSLocalizedString("Call without notification", comment: ""),
                                            image: silentImage) { [unowned self] _ in
                startCallSilently.toggle()
                setupCallOptionsBarButtonMenu(button: button)
            }

            silentCallAction.attributes = [.keepsMenuPresented]
            silentCallAction.accessibilityIdentifier = "Call without notification"
            silentCallAction.accessibilityHint = NSLocalizedString("Double tap to enable or disable 'Call without notification' option", comment: "")

            let silentMenu = UIMenu(title: "", options: [.displayInline], children: [silentCallAction])
            callOptions.append(silentMenu)
        }

        button.innerButton.menu = UIMenu(title: "", children: callOptions)
        button.innerButton.showsMenuAsPrimaryAction = true
    }

    func startCall(withVideo video: Bool, silently: Bool, button: BarButtonItemWithActivity) {
        button.showIndicator()
        if self.room.recordingConsent {
            let alert = UIAlertController(title: "⚠️" + NSLocalizedString("The call might be recorded", comment: ""),
                                          message: NSLocalizedString("The recording might include your voice, video from camera, and screen share. Your consent is required before joining the call.", comment: ""),
                                          preferredStyle: .alert)

            alert.addAction(.init(title: NSLocalizedString("Give consent and join call", comment: "Give consent to the recording of the call and join that call"), style: .default) { _ in
                CallKitManager.sharedInstance().startCall(self.room.token, withVideoEnabled: video, andDisplayName: self.room.displayName, asInitiator: !self.room.hasCall, silently: silently, recordingConsent: true, withAccountId: self.room.accountId)
            })

            alert.addAction(.init(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                button.hideIndicator()
            })

            NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)

        } else {
            CallKitManager.sharedInstance().startCall(self.room.token, withVideoEnabled: video, andDisplayName: self.room.displayName, asInitiator: !self.room.hasCall, silently: silently, recordingConsent: false, withAccountId: self.room.accountId)
        }
    }

    private lazy var closeButton: UIBarButtonItem = {
        let closeButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)

        closeButton.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            if self.presentedInCall {
                NCRoomsManager.sharedInstance().callViewController?.toggleChatView()
            } else {
                self.leaveChat()
                self.dismiss(animated: true)
            }
        })

        closeButton.accessibilityIdentifier = "closeChatButton"

        return closeButton
    }()

    private lazy var threadNotificationButton: UIBarButtonItem = {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16)
        let buttonImage = UIImage(systemName: "bell", withConfiguration: symbolConfiguration) ?? UIImage()
        let button = BarButtonItemWithActivity(image: buttonImage)

        self.setupThreadNotificationButtonMenu(button: button)

        button.accessibilityLabel = NSLocalizedString("Thread notification level button", comment: "")
        button.accessibilityHint = NSLocalizedString("Double tap to display thread notification level options", comment: "")

        return button
    }()

    func setupThreadNotificationButtonMenu(button: BarButtonItemWithActivity) {
        guard let thread = thread else { return }

        let options = NotificationLevelOption.allCases.map { option in
            UIAction(
                title: option.title,
                subtitle: option.subtitle,
                image: option.image,
                state: option.value == thread.notificationLevel ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                button.showIndicator()
                NCAPIController.sharedInstance().setNotificationLevelForThread(
                    for: self.account.accountId,
                    in: self.room.token,
                    threadId: thread.threadId,
                    level: option.value
                ) { updatedThread in
                    DispatchQueue.main.async {
                        button.hideIndicator()
                        if let updatedThread {
                            self.thread = updatedThread
                            self.setupThreadNotificationButtonMenu(button: button)
                            if updatedThread.notificationLevel != NotificationLevelOption.off.rawValue {
                                NCDatabaseManager.sharedInstance().updateHasThreads(forAccountId: self.account.accountId, with: true)
                            }
                        }
                    }
                }
            }
        }

        if let currentOption = NotificationLevelOption.allCases.first(where: { $0.value == thread.notificationLevel }),
           let currentOptionImage = currentOption.image {
            button.setImage(currentOptionImage)
        }

        button.innerButton.menu = UIMenu(options: .displayInline, children: options)
        button.innerButton.showsMenuAsPrimaryAction = true
    }

    private lazy var callOptionsButton: BarButtonItemWithActivity = {
        let callOptionsButton = self.getCallOptionsBarButton()

        callOptionsButton.accessibilityLabel = NSLocalizedString("Call options", comment: "")
        callOptionsButton.accessibilityHint = NSLocalizedString("Double tap to display call options", comment: "")

        return callOptionsButton
    }()

    private lazy var optionMenuButton: BarButtonItemWithActivity = {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16)
        let buttonImage = UIImage(systemName: "ellipsis.circle", withConfiguration: symbolConfiguration) ?? UIImage()
        let button = BarButtonItemWithActivity(image: buttonImage)

        button.innerButton.menu = createOptionsRoomMenu()
        button.innerButton.showsMenuAsPrimaryAction = true

        button.accessibilityLabel = NSLocalizedString("Option menu", comment: "A menu to show additional options for the current conversation")
        button.accessibilityHint = NSLocalizedString("Double tap to display option menu", comment: "A menu to show additional options for the current conversation")

        return button
    }()

    private func createOptionsRoomMenu() -> UIMenu {
        var menuElements: [UIMenuElement] = []

        if room.supportsUpcomingEvents {
            menuElements.append(self.createEventsMenu())
        }

        if room.supportsThreading {
            menuElements.append(self.createThreadingRoomMenu())
        }

        return UIMenu(options: [.displayInline], children: menuElements)
    }

    private func createThreadingRoomMenu() -> UIMenu {
        let deferredMenuElement = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { return }

            NCAPIController.sharedInstance().getThreads(for: self.account.accountId, in: self.room.token, withLimit: 5) { threads in
                guard let threads, !threads.isEmpty else {
                    completion([UIAction(title: NSLocalizedString("No recent threads", comment: ""), attributes: .disabled, handler: { _ in })])
                    return
                }

                var actions: [UIAction] = []
                let menuCreationGroup = DispatchGroup()

                for thread in threads {
                    menuCreationGroup.enter()

                    let message = thread.lastMessage() ?? thread.firstMessage()

                    let action = UIAction(title: thread.title, handler: { _ in
                        guard let message else { return }
                        self.didPressShowThread(for: message)
                    })

                    actions.append(action)

                    guard let message else {
                        menuCreationGroup.leave()
                        continue
                    }

                    action.subtitle = message.messagePreview()?.string
                    if let image = AvatarManager.shared.getThreadAvatar(for: thread, with: self.traitCollection.userInterfaceStyle) {
                        action.image = NCUtils.roundedImage(fromImage: image)
                    }

                    menuCreationGroup.leave()
                }

                // TODO: Add a "More threads" button if the limit was returned and open a dedicated view?

                menuCreationGroup.notify(queue: .main) {
                    completion(actions)
                }
            }
        }

        return UIMenu(title: NSLocalizedString("Recent threads", comment: ""), options: [.displayInline], children: [deferredMenuElement])
    }

    private func createEventsMenu() -> UIMenu {
        if self.room.isEvent {
            return self.createEventsRoomMenu()
        } else {
            return self.createUpcomingEventsMenu()
        }
    }

    private func createEventsRoomMenu() -> UIMenu {
        guard let calendarEvent = self.room.calendarEvent else {
            return UIMenu(children: [UIAction(title: NSLocalizedString("No upcoming events", comment: ""), attributes: .disabled, handler: { _ in })])
        }

        var menuElements: [UIMenuElement] = []

        menuElements.append(UIAction(title: NSLocalizedString("Schedule", comment: "Noun. 'Schedule' of a meeting"), subtitle: calendarEvent.readableStartTime(), handler: { _ in }))

        if self.room.canModerate, calendarEvent.isPastEvent {
            let deleteConversation = UIAction(title: NSLocalizedString("Delete conversation", comment: ""), image: .init(systemName: "trash")) { [unowned self] _ in
                NCRoomsManager.sharedInstance().deleteRoom(withConfirmation: self.room, withStartedBlock: nil)
            }

            deleteConversation.attributes = .destructive

            let deleteMenu = UIMenu(title: "", options: [.displayInline], children: [deleteConversation])
            menuElements.append(deleteMenu)
        }

        return UIMenu(title: "", options: [.displayInline], children: menuElements)
    }

    private func createUpcomingEventsMenu() -> UIMenu {
        let deferredUpcomingEvents = UIDeferredMenuElement { [weak self] completion in
            guard let self = self else { return }

            NCAPIController.sharedInstance().upcomingEvents(self.room, forAccount: self.account) { events in
                let actions: [UIAction]
                if !events.isEmpty {
                    actions = events.map { event in
                        UIAction(title: event.summary, subtitle: event.readableStartTime(), handler: { _ in })
                    }
                } else {
                    actions = [UIAction(title: NSLocalizedString("No upcoming events", comment: ""), attributes: .disabled, handler: { _ in })]
                }

                completion(actions)
            }
        }

        var menuElements: [UIMenuElement] = [deferredUpcomingEvents]

        if self.room.canModerate || self.room.type == .oneToOne {
            let scheduleMeetingAction = UIAction(title: NSLocalizedString("Schedule a meeting", comment: ""), image: UIImage(systemName: "calendar.badge.plus")) { [unowned self] _ in
                let scheduleMeetingView = ScheduleMeetingSwiftUIView(account: self.account, room: self.room) {
                    self.handleMeetingCreationSuccess()
                }
                let hostingController = UIHostingController(rootView: scheduleMeetingView)
                self.present(hostingController, animated: true)
            }

            menuElements.append(scheduleMeetingAction)
        }

        return UIMenu(title: NSLocalizedString("Meetings", comment: "Headline for a 'meeting section'"), options: [.displayInline], children: menuElements)
    }

    private func handleMeetingCreationSuccess() {
        // Re-create menu so upcoming events are refetched
        optionMenuButton.innerButton.menu = createOptionsRoomMenu()
    }

    private var messageExpirationTimer: Timer?

    override func setTitleView() {
        super.setTitleView()

        if isThreadViewController {
            self.titleView?.update(for: thread)
            self.titleView?.longPressGestureRecognizer.isEnabled = false
        }
    }

    public override init?(forRoom room: NCRoom, withAccount account: TalkAccount) {
        self.chatController = NCChatController(for: room)

        super.init(forRoom: room, withAccount: account)

        self.addCommonNotificationObservers()
    }

    public init?(forThread thread: NCThread, inRoom room: NCRoom, withAccount account: TalkAccount) {
        self.chatController = NCChatController(forThreadId: thread.threadId, in: room)

        super.init(forRoom: room, withAccount: account)

        self.thread = thread

        self.addCommonNotificationObservers()
    }

    func addCommonNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didUpdateRoom(notification:)), name: NSNotification.Name.NCRoomsManagerDidUpdateRoom, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didJoinRoom(notification:)), name: NSNotification.Name.NCRoomsManagerDidJoinRoom, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didLeaveRoom(notification:)), name: NSNotification.Name.NCRoomsManagerDidLeaveRoom, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveInitialChatHistory(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveInitialChatHistory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveInitialChatHistoryOffline(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveInitialChatHistoryOffline, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveChatHistory(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveChatHistory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveChatMessages(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveChatMessages, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didSendChatMessage(notification:)), name: NSNotification.Name.NCChatControllerDidSendChatMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveChatBlocked(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveChatBlocked, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveNewerCommonReadMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveNewerCommonReadMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveCallStartedMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveCallStartedMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveCallEndedMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveCallEndedMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveUpdateMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveUpdateMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveThreadMessage(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveThreadMessage, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveHistoryCleared(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveHistoryCleared, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMessagesInBackground(notification:)), name: NSNotification.Name.NCChatControllerDidReceiveMessagesInBackground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeRoomCapabilities(notification:)), name: NSNotification.Name.NCDatabaseManagerRoomCapabilitiesChanged, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveParticipantJoin(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidReceiveJoinOfParticipant, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveParticipantLeave(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidReceiveLeaveOfParticipant, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveStartedTyping(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidReceiveStartedTyping, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveStoppedTyping(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidReceiveStoppedTyping, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didFailRequestingCallTransaction(notification:)), name: NSNotification.Name.CallKitManagerDidFailRequestingCallTransaction, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didUpdateParticipants(notification:)), name: NSNotification.Name.NCExternalSignalingControllerDidUpdateParticipants, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(notification:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive(notification:)), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectionStateHasChanged(notification:)), name: NSNotification.Name.NCConnectionStateHasChangedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(maintenanceModeActive(notification:)), name: NSNotification.Name.NCServerMaintenanceMode, object: nil)

        // Notifications when runing on Mac
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(notification:)), name: NSNotification.Name(rawValue: "NSApplicationDidBecomeActiveNotification"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive(notification:)), name: NSNotification.Name(rawValue: "NSApplicationDidResignActiveNotification"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("Dealloc NewChatViewController")
    }

    // MARK: - View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Right bar button items
        var barButtonsItems: [UIBarButtonItem] = []

        if presentedInCall {
            barButtonsItems = [closeButton]
        } else if isThreadViewController {
            barButtonsItems = [closeButton, threadNotificationButton]
        } else {
            // Option menu
            if room.supportsUpcomingEvents || room.supportsThreading {
                barButtonsItems.append(optionMenuButton)
            }
            // Call options
            if room.supportsCalling {
                barButtonsItems.append(callOptionsButton)
            }
        }

        self.navigationItem.rightBarButtonItems = barButtonsItems

        // No sharing options in federation v1 (or thread view until implemented)
        if room.isFederated {
            // When hiding the button it is still respected in the layout constraints
            // So we need to remove the image to remove the button for now
            self.leftButton.setImage(nil, for: .normal)
        }

        // Disable room info, input bar and call buttons until joining room
        self.disableRoomControls()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.checkLobbyState()
        self.checkRoomControlsAvailability()
        self.checkOutOfOfficeAbsence()
        self.checkRetention()

        self.startObservingExpiredMessages()

        // Workaround for open conversations:
        // We can't get initial chat history until we join the conversation (since we are not a participant until then)
        // So for rooms that we don't know the last read message we wait until we join the room to get the initial chat history.
        if !self.hasReceiveInitialHistory, !self.hasRequestedInitialHistory, self.room.lastReadMessage > 0 {
            self.hasRequestedInitialHistory = true
            self.chatController.getInitialChatHistory()
        }

        if !self.offlineMode {
            NCRoomsManager.sharedInstance().joinRoom(self.room.token, forCall: false)
        }

        // Check if there are summary tasks still running, but not yet finished
        if !AiSummaryController.shared.getSummaryTaskIds(forRoomInternalId: self.room.internalId).isEmpty {
            self.showGeneratingSummaryNotification()
            self.scheduleSummaryTaskCheck()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if self.presentKeyboardOnAppear {
            self.presentKeyboard(true)
            self.presentKeyboardOnAppear = false
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        self.saveLastReadMessage()
        self.stopVoiceMessagePlayer()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if self.isMovingFromParent {
            self.leaveChat()
        }

        self.callOptionsButton.hideIndicator()
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - App lifecycle

    func appDidBecomeActive(notification: Notification) {
        // Don't handle this event if the view is not loaded yet.
        // Otherwise we try to join the room and receive new messages while
        // viewDidLoad wasn't called, resulting in uninitialized dictionaries and crashes
        if !self.isViewLoaded {
            return
        }

        // If we stopped the chat, we don't want to resume it here
        if self.hasStopped {
            return
        }

        // Check if new messages were added while the app was inactive (eg. via background-refresh)
        self.checkForNewStoredMessages()

        if !self.offlineMode {
            NCRoomsManager.sharedInstance().joinRoom(self.room.token, forCall: false)
        }

        self.startObservingExpiredMessages()
    }

    func appWillResignActive(notification: Notification) {
        // If we stopped the chat, we don't want to change anything here
        if self.hasStopped {
            return
        }

        self.startReceivingMessagesAfterJoin = true
        self.removeUnreadMessagesSeparator()
        self.savePendingMessage()
        self.chatController.stop()
        self.messageExpirationTimer?.invalidate()
        self.stopTyping(force: false)
        NCRoomsManager.sharedInstance().leaveChat(inRoom: self.room.token)
    }

    func connectionStateHasChanged(notification: Notification) {
        guard let rawConnectionState = notification.userInfo?["connectionState"] as? Int, let connectionState = ConnectionState(rawValue: rawConnectionState) else {
            return
        }

        switch connectionState {
        case .connected:
            if offlineMode {
                offlineMode = false
                startReceivingMessagesAfterJoin = true
                self.removeOfflineFooterView()
                NCRoomsManager.sharedInstance().joinRoom(self.room.token, forCall: false)
            }
        default:
            break
        }
    }

    func maintenanceModeActive(notification: Notification) {
        self.setOfflineMode()
    }

    // MARK: - User Interface

    func disableRoomControls() {
        self.titleView?.isUserInteractionEnabled = false

        self.callOptionsButton.hideIndicator()
        self.callOptionsButton.isEnabled = false

        self.rightButton.isEnabled = false
        self.leftButton.isEnabled = false
    }

    func checkRoomControlsAvailability() {
        if hasJoinedRoom, !offlineMode {
            // Enable room info and call buttons when we joined a room
            self.titleView?.isUserInteractionEnabled = true
            self.callOptionsButton.isEnabled = true
        }

        // Files/objects can only be send when we're not offline
        self.leftButton.isEnabled = !offlineMode

        // Always allow to start writing a message, even if we didn't join the room (yet)
        self.rightButton.isEnabled = self.canPressRightButton()
        self.textInputbar.isUserInteractionEnabled = true

        if !room.userCanStartCall, !room.hasCall {
            // Disable call buttons
            self.callOptionsButton.isEnabled = false
        }

        // Configure inCall state for call button
        self.configureCallButtonAsInCall(button: callOptionsButton, inCall: room.hasCall)

        if room.readOnlyState == .readOnly || self.shouldPresentLobbyView() {
            // Hide text input
            self.setTextInputbarHidden(true, animated: self.isVisible)

            // Disable call buttons
            self.callOptionsButton.isEnabled = false
        } else if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityChatPermission, for: room), !room.permissions.contains(.chat) {
            // Hide text input
            self.setTextInputbarHidden(true, animated: isVisible)
        } else if self.isTextInputbarHidden {
            // Show text input if it was hidden in a previous state
            self.setTextInputbarHidden(false, animated: isVisible)

            if self.tableView?.slk_isAtBottom ?? false {
                self.tableView?.slk_scrollToBottom(animated: true)
            }

            // Make sure the textinput has the correct height
            self.setChatMessage(self.textInputbar.textView.text)
        }

        // Rebuild the call menu to reflect the current call state
        self.setupCallOptionsBarButtonMenu(button: self.callOptionsButton)
    }

    func checkLobbyState() {
        if self.shouldPresentLobbyView() {
            self.hasPresentedLobby = true

            var placeholderText = NSLocalizedString("You are currently waiting in the lobby", comment: "")

            // Lobby timer
            if self.room.lobbyTimer > 0 {
                let date = Date(timeIntervalSince1970: TimeInterval(self.room.lobbyTimer))
                let meetingStart = NCUtils.readableDateTime(fromDate: date)
                let meetingStartPlaceholder = NSLocalizedString("This meeting is scheduled for", comment: "The meeting start time will be displayed after this text e.g (This meeting is scheduled for tomorrow at 10:00)")
                placeholderText += "\n\n\(meetingStartPlaceholder)\n\(meetingStart)"
            }

            // Room description
            if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityRoomDescription, for: room), !self.room.roomDescription.isEmpty {
                placeholderText += "\n\n" + self.room.roomDescription
            }

            // Only set it when text changes to avoid flickering in links
            if chatBackgroundView.placeholderTextView.text != placeholderText {
                chatBackgroundView.placeholderTextView.text = placeholderText
            }

            self.chatBackgroundView.setImage(UIImage(named: "lobby-placeholder"))
            self.chatBackgroundView.placeholderView.isHidden = false
            self.chatBackgroundView.loadingView.stopAnimating()
            self.chatBackgroundView.loadingView.isHidden = true

            // Clear current chat since chat history will be retrieved when lobby is disabled
            self.cleanChat()
        } else {
            self.chatBackgroundView.setImage(UIImage(named: "chat-placeholder"))
            self.chatBackgroundView.placeholderTextView.text = NSLocalizedString("No messages yet, start the conversation!", comment: "")
            self.chatBackgroundView.placeholderView.isHidden = true
            self.chatBackgroundView.loadingView.startAnimating()
            self.chatBackgroundView.loadingView.isHidden = false

            // Stop checking lobby flag
            self.lobbyCheckTimer?.invalidate()

            // Retrieve initial chat history if lobby was enabled and we didn't retrieve it before
            if !hasReceiveInitialHistory, !hasRequestedInitialHistory, hasPresentedLobby {
                self.hasRequestedInitialHistory = true
                self.chatController.getInitialChatHistory()
            }

            self.hasPresentedLobby = false
        }
    }

    func setOfflineFooterView() {
        let isAtBottom = self.shouldScrollOnNewMessages()

        let footerLabel = UILabel(frame: .init(x: 0, y: 0, width: 350, height: 24))
        footerLabel.textAlignment = .center
        footerLabel.textColor = .label
        footerLabel.font = .systemFont(ofSize: 12)
        footerLabel.backgroundColor = .clear
        footerLabel.text = NSLocalizedString("Offline, only showing downloaded messages", comment: "")

        self.tableView?.tableFooterView = footerLabel
        self.tableView?.tableFooterView?.backgroundColor = .secondarySystemBackground

        if isAtBottom {
            self.tableView?.slk_scrollToBottom(animated: true)
        }
    }

    func removeOfflineFooterView() {
        DispatchQueue.main.async {
            self.tableView?.tableFooterView?.removeFromSuperview()
            self.tableView?.tableFooterView = nil

            // Scrolling after removing the tableFooterView won't scroll all the way to the bottom therefore just keep the current position
            // And don't try to call scrollToBottom
        }
    }

    func setOfflineMode() {
        self.offlineMode = true
        self.setOfflineFooterView()
        self.chatController.stopReceivingNewChatMessages()
        self.disableRoomControls()
        self.checkRoomControlsAvailability()
    }

    // MARK: - Out Of Office

    let outOfOfficeView: OutOfOfficeView? = nil

    func checkOutOfOfficeAbsence() {
        // Only check once, and only for 1:1 on DND right now
        guard self.hasCheckedOutOfOfficeStatus == false,
              self.room.type == .oneToOne,
              self.room.status == kUserStatusDND,
              let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.room.accountId),
              serverCapabilities.absenceSupported
        else { return }

        self.hasCheckedOutOfOfficeStatus = true

        NCAPIController.sharedInstance().getCurrentUserAbsence(forAccountId: self.room.accountId, forUserId: self.room.name) { absenceData in
            guard let absenceData else { return }

            let oooView = OutOfOfficeView()
            oooView.setupAbsence(withData: absenceData, inRoom: self.room)
            oooView.alpha = 0

            self.view.addSubview(oooView)

            NSLayoutConstraint.activate([
                oooView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
                oooView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
                oooView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor)
            ])

            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
                oooView.alpha = 1.0
            }
        }
    }

    // MARK: - Room retention

    var retentionView: ChatInfoView? = nil

    func checkRetention() {
        // Only check for event conversations that have ended
        // TODO: check if there are end_call messages
        guard self.room.isEvent,
              self.room.isPastEvent,
              let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.room.accountId),
              serverCapabilities.retentionEvent > 0
        else {
            self.retentionView?.removeFromSuperview()
            return
        }

        guard self.retentionView == nil else { return }

        let retentionView = ChatInfoView()
        self.retentionView = retentionView

        retentionView.titleLabel.text = String.localizedStringWithFormat(
            NSLocalizedString("This conversation will be automatically deleted for everyone in %ld days of no activity.", comment: ""),
            serverCapabilities.retentionEvent)
        retentionView.leftButton.setTitle(NSLocalizedString("Delete now", comment: ""), for: .normal)
        retentionView.leftButton.setButtonStyle(style: .destructive)
        retentionView.leftButton.setButtonAction(target: self, selector: #selector(deleteNowButtonPressed))
        retentionView.rightButton.setTitle(NSLocalizedString("Keep", comment: ""), for: .normal)
        retentionView.rightButton.setButtonStyle(style: .primary)
        retentionView.rightButton.setButtonAction(target: self, selector: #selector(keepButtonPressed))
        retentionView.alpha = 0

        self.view.addSubview(retentionView)

        NSLayoutConstraint.activate([
            retentionView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
            retentionView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
            retentionView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor)
        ])

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
            retentionView.alpha = 1.0
        }
    }

    func deleteNowButtonPressed() {
        NCRoomsManager.sharedInstance().deleteRoom(withConfirmation: self.room, withStartedBlock: nil)
    }

    func keepButtonPressed() {
        NCAPIController.sharedInstance().unbindRoomFromObject(self.room.token, forAccount: self.account) { error in
            if error != nil {
                print("Error unbinding room from object")
                return
            }

            self.updateRoomInformation()
        }
    }

    // MARK: - Message expiration

    func startObservingExpiredMessages() {
        self.messageExpirationTimer?.invalidate()
        self.removeExpiredMessages()
        self.messageExpirationTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true, block: { [weak self] _ in
            self?.removeExpiredMessages()
        })
    }

    func removeExpiredMessages() {
        DispatchQueue.main.async {
            let currentTimestamp = Int(Date().timeIntervalSince1970)

            // Iterate backwards in case we need to delete multiple sections in one go
            for sectionIndex in self.dateSections.indices.reversed() {
                let section = self.dateSections[sectionIndex]

                guard let messages = self.messages[section] else { continue }

                let deleteMessages = messages.filter { message in
                    return message.expirationTimestamp > 0 && message.expirationTimestamp <= currentTimestamp
                }

                if !deleteMessages.isEmpty {
                    self.tableView?.beginUpdates()

                    let filteredMessages = messages.filter { !deleteMessages.contains($0) }
                    self.messages[section] = filteredMessages

                    if !filteredMessages.isEmpty {
                        self.tableView?.reloadSections(IndexSet(integer: sectionIndex), with: .top)
                    } else {
                        self.messages.removeValue(forKey: section)
                        self.sortDateSections()
                        self.tableView?.deleteSections(IndexSet(integer: sectionIndex), with: .top)
                    }

                    self.tableView?.endUpdates()
                }
            }

            self.chatController.removeExpiredMessages()
        }
    }

    // MARK: - Utils

    func presentJoinError(_ subtitle: String) {
        NotificationPresenter.shared().present(title: NSLocalizedString("Could not join conversation", comment: ""), subtitle: subtitle, includedStyle: .warning)
        NotificationPresenter.shared().dismiss(afterDelay: 8.0)
    }

    // MARK: - Action methods

    override func sendChatMessage(message: String, withParentMessage parentMessage: NCChatMessage?, messageParameters: String, silently: Bool) {
        var replyTo = parentMessage

        // On thread view, include original thread message as parent message (if there is not parent)
        if let thread = thread, replyTo == nil {
            replyTo = thread.firstMessage()
        }

        // Create temporary message
        guard let temporaryMessage = self.createTemporaryMessage(message: message, replyTo: replyTo, messageParameters: messageParameters, silently: silently, isVoiceMessage: false) else { return }

        if NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityChatReferenceId, for: room) {
            self.appendTemporaryMessage(temporaryMessage: temporaryMessage)
        }

        // Send message
        self.chatController.send(temporaryMessage)
    }

    public override func canPressRightButton() -> Bool {
        let canPress = super.canPressRightButton()

        if self.textInputbar.isEditing {
            // When we're editing, we can use the default implementation, as we don't want to save an empty message
            return canPress
        }

        // If in offline mode, we don't want to show the voice button
        if !offlineMode, !canPress, !presentedInCall,
           NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityVoiceMessage, for: room),
           !room.isFederated {

            self.showVoiceMessageRecordButton()
            return true
        }

        self.showSendMessageButton()

        return canPress
    }

    public override func didPressShowThread(for message: NCChatMessage, toReply: Bool = false) {
        guard let account = self.room.account,
              let thread = NCThread(threadId: message.threadId, inRoom: room.token, forAccountId: account.accountId),
              let chatViewController = ChatViewController(forThread: thread, inRoom: room, withAccount: account)
        else { return }

        chatViewController.presentKeyboardOnAppear = toReply

        let navController = NCNavigationController(rootViewController: chatViewController)
        navController.presentationController?.delegate = chatViewController
        self.present(navController, animated: true)
    }

    // MARK: - Voice message player
    // Override the default implementation to don't hijack the audio session when presented in a call

    override func playVoiceMessagePlayer() {
        if !self.presentedInCall {
            self.setSpeakerAudioSession()
            self.enableProximitySensor()
        }

        self.startVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.play()
    }

    override func pauseVoiceMessagePlayer() {
        if !self.presentedInCall {
            self.disableProximitySensor()
        }

        self.stopVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.pause()
        self.checkVisibleCellAudioPlayers()
    }

    override func stopVoiceMessagePlayer() {
        if !self.presentedInCall {
            self.disableProximitySensor()
        }

        self.stopVoiceMessagePlayerTimer()
        self.voiceMessagesPlayer?.stop()
    }

    override func sensorStateChange(notification: Notification) {
        if self.presentedInCall {
            return
        }

        if UIDevice.current.proximityState {
            self.setVoiceChatAudioSession()
        } else {
            self.pauseVoiceMessagePlayer()
            self.setSpeakerAudioSession()
            self.disableProximitySensor()
        }
    }

    // MARK: - UIScrollViewDelegate methods

    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)

        guard scrollView == self.tableView,
              scrollView.contentOffset.y < 0,
              self.couldRetrieveHistory()
        else { return }

        if let firstMessage = self.getFirstRealMessage()?.message,
            self.chatController.hasHistory(fromMessageId: firstMessage.messageId) {

            self.retrievingHistory = true
            self.showLoadingHistoryView()

            if self.offlineMode {
                self.chatController.getHistoryBatchOffline(fromMessagesId: firstMessage.messageId)
            } else {
                self.chatController.getHistoryBatch(fromMessagesId: firstMessage.messageId)
            }
        }
    }

    public func stopChat() {
        self.hasStopped = true
        self.chatController.stop()
        self.cleanChat()
    }

    public func resumeChat() {
        self.hasStopped = false

        if !self.hasReceiveInitialHistory, !self.hasRequestedInitialHistory {
            self.hasRequestedInitialHistory = true
            self.chatController.getInitialChatHistory()
        }
    }

    public func leaveChat() {
        self.hasStopped = true
        self.lobbyCheckTimer?.invalidate()
        self.messageExpirationTimer?.invalidate()
        self.generateSummaryTimer?.invalidate()
        self.chatController.stop()

        // Dismiss possible notifications
        // swiftlint:disable:next notification_center_detachment
        NotificationCenter.default.removeObserver(self)

        // In case we're typing when we leave the chat, make sure we notify everyone
        // The 'stopTyping' method makes sure to only send signaling messages when we were typing before
        self.stopTyping(force: false)

        // If this is a thread view, we can leave at this point
        if self.isThreadViewController {
            return
        }

        // If this chat view controller is for the same room as the one owned by the rooms manager
        // then we should not try to leave the chat. Since we will leave the chat when the
        // chat view controller owned by rooms manager moves from parent view controller.
        if NCRoomsManager.sharedInstance().chatViewController?.room.token == self.room.token,
           NCRoomsManager.sharedInstance().chatViewController !== self {
            return
        }

        NCRoomsManager.sharedInstance().leaveChat(inRoom: self.room.token)

        // Remove chat view controller pointer if this chat is owned by rooms manager
        // and the chat view is moving from parent view controller
        if NCRoomsManager.sharedInstance().chatViewController === self {
            NCRoomsManager.sharedInstance().chatViewController = nil
        }
    }

    public override func cleanChat() {
        super.cleanChat()

        self.hasReceiveInitialHistory = false
        self.hasRequestedInitialHistory = false
        self.chatController.hasReceivedMessagesFromServer = false
    }

    func saveLastReadMessage() {
        NCRoomsManager.sharedInstance().updateLastReadMessage(self.lastReadMessage, for: self.room)
    }

    // MARK: - Room Manager notifications

    func didUpdateRoom(notification: Notification) {
        guard let room = notification.userInfo?["room"] as? NCRoom else { return }

        if room.token != self.room.token {
            return
        }

        self.room = room
        self.setTitleView()

        if !self.hasStopped {
            self.checkLobbyState()
            self.checkRoomControlsAvailability()
        }

        self.checkRetention()
    }

    func didJoinRoom(notification: Notification) {
        guard let token = notification.userInfo?["token"] as? String else { return }

        if token != self.room.token {
            return
        }

        if self.isVisible,
            notification.userInfo?["error"] != nil,
            let errorReason = notification.userInfo?["errorReason"] as? String {

            self.setOfflineMode()
            self.presentJoinError(errorReason)

            if let isBanned = notification.userInfo?["isBanned"] as? Bool, isBanned {
                // Usually we remove all notifications when the view disappears, but in this case, we want to keep it
                self.dismissNotificationsOnViewWillDisappear = false

                // We are not allowed to join this conversation -> Move back to the conversation list
                NCUserInterfaceController.sharedInstance().presentConversationsList()
            }

            return
        }

        if let room = notification.userInfo?["room"] as? NCRoom, room.token == self.room.token {
            self.room = room
        }

        self.hasJoinedRoom = true
        self.checkRoomControlsAvailability()

        if self.hasStopped {
            return
        }

        if self.startReceivingMessagesAfterJoin, self.hasReceiveInitialHistory {
            self.startReceivingMessagesAfterJoin = false
            self.chatController.startReceivingNewChatMessages()
        } else if !self.hasReceiveInitialHistory, !self.hasRequestedInitialHistory {
            self.hasRequestedInitialHistory = true
            self.chatController.getInitialChatHistory()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [capturedToken = self.room.token] in
            // After we joined a room, check if there are offline messages for this particular room which need to be send
            NCRoomsManager.sharedInstance().resendOfflineMessages(forToken: capturedToken, withCompletionBlock: nil)
        }
    }

    func didLeaveRoom(notification: Notification) {
        guard let token = notification.userInfo?["token"] as? String else { return }

        if token != self.room.token {
            return
        }

        if notification.userInfo?["error"] != nil {
            // In case an error occurred when leaving the room, we assume we are still joined
            return
        }

        self.hasJoinedRoom = false
        self.disableRoomControls()
        self.checkRoomControlsAvailability()
    }

    // MARK: - CallKit Manager notifications

    func didFailRequestingCallTransaction(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String else { return }

        if token != self.room.token {
            return
        }

        DispatchQueue.main.async {
            self.callOptionsButton.hideIndicator()
        }
    }

    // MARK: - Chat Controller notifications

    // swiftlint:disable:next cyclomatic_complexity
    func didReceiveInitialChatHistory(notification: Notification) {
        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController {
                return
            }

            if self.shouldPresentLobbyView() {
                self.hasRequestedInitialHistory = false
                self.startObservingRoomLobbyFlag()

                return
            }

            if let messages = notification.userInfo?["messages"] as? [NCChatMessage], !messages.isEmpty {

                var indexPathUnreadMessageSeparator: IndexPath?
                let lastMessage = messages.reversed().first(where: { !$0.isUpdateMessage })

                self.appendMessages(messages: messages)

                if let lastMessage, lastMessage.messageId > self.lastReadMessage {
                    // Iterate backwards to find the correct location for the unread message separator
                    for sectionIndex in self.dateSections.indices.reversed() {
                        let dateSection: Date = self.dateSections[sectionIndex]

                        guard var messages = self.messages[dateSection] else { continue }

                        for messageIndex in messages.indices.reversed() {
                            let message = messages[messageIndex]

                            if message.messageId > self.lastReadMessage {
                                continue
                            }

                            // Store the messageId separately from self.lastReadMessage as that might change during a room update
                            self.generateSummaryFromMessageId = message.messageId
                            messages.insert(self.unreadMessagesSeparator, at: messageIndex + 1)
                            self.messages[dateSection] = messages
                            indexPathUnreadMessageSeparator = IndexPath(row: messageIndex + 1, section: sectionIndex)

                            break
                        }

                        if indexPathUnreadMessageSeparator != nil {
                            break
                        }
                    }

                    self.lastReadMessage = lastMessage.messageId
                }

                let storedTemporaryMessages = self.chatController.getTemporaryMessages()

                if !storedTemporaryMessages.isEmpty {
                    self.insertMessages(messages: storedTemporaryMessages)

                    if indexPathUnreadMessageSeparator != nil {
                        // It is possible that temporary messages are added which add new sections
                        // In this case the indexPath of the unreadMessageSeparator would be invalid and could lead to a crash
                        // Therefore we need to make sure we got the correct indexPath here
                        indexPathUnreadMessageSeparator = self.indexPathForUnreadMessageSeparator()
                    }
                }

                self.tableView?.reloadData()

                if let indexPathUnreadMessageSeparator {
                    self.tableView?.scrollToRow(at: indexPathUnreadMessageSeparator, at: .middle, animated: false)
                } else {
                    self.tableView?.slk_scrollToBottom(animated: false)
                }

                self.updateToolbar(animated: false)
            } else {
                self.chatBackgroundView.placeholderView.isHidden = false
            }

            self.hasReceiveInitialHistory = true

            if notification.userInfo?["error"] == nil {
                self.chatController.startReceivingNewChatMessages()
            } else {
                self.offlineMode = true
                self.chatController.getInitialChatHistoryForOfflineMode()
            }
        }
    }

    func didReceiveInitialChatHistoryOffline(notification: Notification) {
        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController {
                return
            }

            if let messages = notification.userInfo?["messages"] as? [NCChatMessage], !messages.isEmpty {
                self.appendMessages(messages: messages)
                self.setOfflineFooterView()
                self.tableView?.reloadData()
                self.tableView?.slk_scrollToBottom(animated: false)
                self.updateToolbar(animated: false)
            } else {
                self.chatBackgroundView.placeholderView.isHidden = false
            }

            let storedTemporaryMessages = self.chatController.getTemporaryMessages()

            if !storedTemporaryMessages.isEmpty {

                self.insertMessages(messages: storedTemporaryMessages)
                self.tableView?.reloadData()
                self.tableView?.slk_scrollToBottom(animated: false)
                self.updateToolbar(animated: false)
            }
        }
    }

    func didReceiveChatHistory(notification: Notification) {
        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController {
                return
            }

            if let messages = notification.userInfo?["messages"] as? [NCChatMessage], !messages.isEmpty {

                let shouldAddBlockSeparator = notification.userInfo?["shouldAddBlockSeparator"] as? Bool ?? false

                if let lastHistoryMessageIP = self.prependMessages(historyMessages: messages, addingBlockSeparator: shouldAddBlockSeparator),
                   let tableView = self.tableView {

                    self.tableView?.reloadData()

                    if tableView.isValid(indexPath: lastHistoryMessageIP) {
                        self.tableView?.scrollToRow(at: lastHistoryMessageIP, at: .top, animated: false)
                    }
                }
            }

            if notification.userInfo?["noMoreStoredHistory"] as? Bool == true {
                self.hasStoredHistory = false
            }

            self.retrievingHistory = false
            self.hideLoadingHistoryView()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func didReceiveChatMessages(notification: Notification) {
        // If we receive messages in the background, we should make sure that our update here completely run
        let bgTask = BGTaskHelper.startBackgroundTask(withName: "didReceiveChatMessages")

        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController || notification.userInfo?["error"] != nil {
                bgTask.stopBackgroundTask()
                return
            }

            let firstNewMessagesAfterHistory = notification.userInfo?["firstNewMessagesAfterHistory"] as? Bool ?? false

            if let messages = notification.userInfo?["messages"] as? [NCChatMessage], let tableView = self.tableView, !messages.isEmpty {
                // Detect if we should scroll to new messages before we issue a reloadData
                // Otherwise longer messages will prevent scrolling
                let shouldScrollOnNewMessages = self.shouldScrollOnNewMessages()
                let newMessagesContainVisibleMessages = messages.containsVisibleMessages()

                // Use a Set here so we don't have to deal with duplicates
                var insertIndexPaths: Set<IndexPath> = []
                var insertSections: IndexSet = []
                var reloadIndexPaths: Set<IndexPath> = []

                var addedUnreadMessageSeparator = false

                // Check if unread messages separator should be added (only if it's not already shown)
                if firstNewMessagesAfterHistory, let lastRealMessage = self.getLastRealMessage(), self.indexPathForUnreadMessageSeparator() == nil, newMessagesContainVisibleMessages,
                   let lastDateSection = self.dateSections.last, var messagesBeforeUpdate = self.messages[lastDateSection] {

                    // Store the messageId separately from self.lastReadMessage as that might change during a room update
                    self.generateSummaryFromMessageId = lastRealMessage.message.messageId
                    messagesBeforeUpdate.append(self.unreadMessagesSeparator)
                    self.messages[lastDateSection] = messagesBeforeUpdate
                    insertIndexPaths.insert(IndexPath(row: messagesBeforeUpdate.count - 1, section: self.dateSections.count - 1))
                    addedUnreadMessageSeparator = true
                }

                self.appendMessages(messages: messages)

                for newMessage in messages {
                    // Update messages might trigger an reload of another cell, but are not part of the tableView itself
                    if newMessage.isUpdateMessage {
                        if let parentMessage = newMessage.parent, let parentPath = self.indexPath(for: parentMessage) {
                            if parentPath.section < tableView.numberOfSections, parentPath.row < tableView.numberOfRows(inSection: parentPath.section) {
                                // We received an update message to a message which is already part of our current data, therefore we need to reload it
                                reloadIndexPaths.insert(parentPath)
                            }
                        }

                        continue
                    }

                    if !self.isThreadViewController, newMessage.isThreadMessage() {
                        // Thread messages should not be displayed outside of threads
                        continue
                    }

                    // If we don't get an indexPath here, something is wrong with our appendMessages function
                    let indexPath = self.indexPath(for: newMessage)!

                    if indexPath.section >= tableView.numberOfSections {
                        // New section -> insert the section
                        insertSections.insert(indexPath.section)
                    }

                    if indexPath.section < tableView.numberOfSections, indexPath.row < tableView.numberOfRows(inSection: indexPath.section) {
                        // This is a already known indexPath, so we want to reload the cell
                        reloadIndexPaths.insert(indexPath)
                    } else {
                        // New indexPath -> insert it
                        insertIndexPaths.insert(indexPath)
                    }

                    if let collapsedByMessage = newMessage.collapsedBy, let collapsedPath = self.indexPath(for: collapsedByMessage) {
                        if collapsedPath.section < tableView.numberOfSections, collapsedPath.row < tableView.numberOfRows(inSection: collapsedPath.section) {
                            // The current message is collapsed, so we need to make sure that the collapsedBy message is reloaded
                            reloadIndexPaths.insert(collapsedPath)
                        }
                    }
                }

                tableView.performBatchUpdates {
                    if !insertSections.isEmpty {
                        tableView.insertSections(insertSections, with: .automatic)
                    }

                    if !insertIndexPaths.isEmpty {
                        tableView.insertRows(at: Array(insertIndexPaths), with: .automatic)
                    }

                    if !reloadIndexPaths.isEmpty {
                        tableView.reloadRows(at: Array(reloadIndexPaths), with: .none)
                    }

                } completion: { _ in
                    // Remove unread messages separator when user writes a message
                    if messages.containsMessage(forUserId: self.account.userId) {
                        self.removeUnreadMessagesSeparator()
                    }

                    // Only scroll to unread message separator if we added it while processing the received messages
                    // Otherwise we would scroll whenever a unread message separator is available
                    if addedUnreadMessageSeparator, let indexPathUnreadMessageSeparator = self.indexPathForUnreadMessageSeparator() {
                        tableView.scrollToRow(at: indexPathUnreadMessageSeparator, at: .middle, animated: true)
                    } else if (shouldScrollOnNewMessages || messages.containsMessage(forUserId: self.account.userId)), let lastIndexPath = self.getLastRealMessage()?.indexPath {
                        tableView.scrollToRow(at: lastIndexPath, at: .none, animated: true)
                    } else if self.firstUnreadMessage == nil, newMessagesContainVisibleMessages, let firstNewMessage = messages.first {
                        // This check is needed since several calls to receiveMessages API might be needed
                        // (if the number of unread messages is bigger than the "limit" in receiveMessages request)
                        // to receive all the unread messages.
                        if firstNewMessage.timestamp >= Int(self.chatViewPresentedTimestamp) {
                            self.showNewMessagesView(until: firstNewMessage)
                        }
                    }

                    // Set last received message as last read message
                    if let lastReceivedMessage = messages.last {
                        self.lastReadMessage = lastReceivedMessage.messageId
                    }
                }

                if firstNewMessagesAfterHistory {
                    self.chatBackgroundView.loadingView.stopAnimating()
                    self.chatBackgroundView.loadingView.isHidden = true
                }

                if self.highlightMessageId > 0, let indexPath = self.indexPathAndMessage(forMessageId: self.highlightMessageId)?.indexPath {
                    self.highlightMessage(at: indexPath, with: .middle)
                    self.highlightMessageId = 0
                }
            }

            bgTask.stopBackgroundTask()
        }
    }

    func didSendChatMessage(notification: Notification) {
        DispatchQueue.main.async {
            if notification.object as? NCChatController != self.chatController {
                return
            }

            if notification.userInfo?["error"] == nil {
                return
            }

            guard let message = notification.userInfo?["message"] as? String else { return }

            if let referenceId = notification.userInfo?["referenceId"] as? String {
                // Got a referenceId -> update the corresponding message
                let isOfflineMessage = notification.userInfo?["isOfflineMessage"] as? Bool ?? false

                self.modifyMessageWith(referenceId: referenceId) { message in
                    message.sendingFailed = !isOfflineMessage
                    message.isOfflineMessage = isOfflineMessage
                }

            } else {
                // No referenceId -> show generic error
                self.textView.text = message

                let alert = UIAlertController(title: NSLocalizedString("Could not send the message", comment: ""),
                                              message: NSLocalizedString("An error occurred while sending the message", comment: ""),
                                              preferredStyle: .alert)

                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
                NCUserInterfaceController.sharedInstance().presentAlertViewController(alert)
            }
        }
    }

    func didReceiveChatBlocked(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        self.startObservingRoomLobbyFlag()
    }

    func didReceiveNewerCommonReadMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        guard let lastCommonReadMessage = notification.userInfo?["lastCommonReadMessage"] as? Int else { return }

        if lastCommonReadMessage > self.room.lastCommonReadMessage {
            self.room.lastCommonReadMessage = lastCommonReadMessage
        }

        self.checkLastCommonReadMessage()
    }

    func didReceiveCallStartedMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        self.room.hasCall = true
        self.checkRoomControlsAvailability()
    }

    func didReceiveCallEndedMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        self.room.hasCall = false
        self.checkRoomControlsAvailability()
    }

    func didReceiveUpdateMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        guard let message = notification.userInfo?["updateMessage"] as? NCChatMessage,
              let updateMessage = message.parent
        else { return }

        self.updateMessage(withMessageId: updateMessage.messageId, updatedMessage: updateMessage)
    }

    func didReceiveThreadMessage(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        guard let message = notification.userInfo?["threadMessage"] as? NCChatMessage else { return }

        if message.isThreadMessage() {
            // Update thread original messages that are already loaded in the chat
            self.updateThreadOriginalMessage(withMessage: message)
            // Update thread info in thread view controllers
            if isThreadViewController {
                thread = NCThread(threadId: message.threadId, inRoom: room.token, forAccountId: account.accountId)
                self.titleView?.update(for: thread)
            }
        }
    }

    func didReceiveHistoryCleared(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        guard let message = notification.userInfo?["historyCleared"] as? NCChatMessage
        else { return }

        if self.chatController.hasOlderStoredMessagesThanMessageId(message.messageId) {
            self.cleanChat()
            self.chatController.clearHistoryAndResetChatController()
            self.hasRequestedInitialHistory = false
            self.chatController.getInitialChatHistory()
        }
    }

    func didReceiveMessagesInBackground(notification: Notification) {
        if notification.object as? NCChatController != self.chatController {
            return
        }

        print("didReceiveMessagesInBackground")
        self.checkForNewStoredMessages()
    }

    // MARK: - Database controller notifications

    func didChangeRoomCapabilities(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String else { return }

        if token != self.room.token {
            return
        }

        self.tableView?.reloadData()
        self.checkRoomControlsAvailability()
    }

    // MARK: - External signaling controller notifications

    func didUpdateParticipants(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String else { return }

        if token != self.room.token {
            return
        }

        let serverSupportsConversationPermissions = NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityConversationPermissions, for: room) ||
                                                    NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityDirectMentionFlag, for: room)

        guard serverSupportsConversationPermissions else { return }

        // Retrieve the information about ourselves
        guard let userDict = notification.userInfo?["users"] as? [[String: String]],
              let appUserDict = userDict.first(where: { $0["userId"] == self.account.userId })
        else { return }

        // Check if we still have the same permissions

        if let permissionsString = appUserDict["participantPermissions"],
           let permissions = Int(permissionsString),
           permissions != self.room.permissions.rawValue {

            // Need to update the room from the api because otherwise "canStartCall" is not updated correctly
            NCRoomsManager.sharedInstance().updateRoom(self.room.token, withCompletionBlock: nil)
        }
    }

    func processTypingNotification(notification: Notification, startedTyping started: Bool) {
        guard let token = notification.userInfo?["roomToken"] as? String,
              let sessionId = notification.userInfo?["sessionId"] as? String,
              token == self.room.token
        else { return }

        // Waiting for https://github.com/nextcloud/spreed/issues/9726 to receive the correct displayname for guests
        let displayName = notification.userInfo?["displayName"] as? String ?? NSLocalizedString("Guest", comment: "")

        // Don't show a typing indicator for ourselves or if typing indicator setting is disabled
        // Workaround: TypingPrivacy should be checked locally, not from the remote server, use serverCapabilities for now
        // TODO: Remove workaround for federated typing indicators.
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.room.accountId)
        else { return }

        let userId = notification.userInfo?["userId"] as? String
        let isFederated = notification.userInfo?["isFederated"] as? Bool ?? false

        // Since our own userId can exist on other servers, only suppress the notification if it's not federated
        if (userId == self.account.userId && !isFederated) || serverCapabilities.typingPrivacy {
            return
        }

        // For guests we use the sessionId as an identifier, for users we use the userId
        var userIdentifier = sessionId

        if let userId, !userId.isEmpty {
            userIdentifier = userId
        }

        if started {
            self.addTypingIndicator(withUserIdentifier: userIdentifier, andDisplayName: displayName)
        } else {
            self.removeTypingIndicator(withUserIdentifier: userIdentifier)
        }
    }

    func didReceiveStartedTyping(notification: Notification) {
        self.processTypingNotification(notification: notification, startedTyping: true)
    }

    func didReceiveStoppedTyping(notification: Notification) {
        self.processTypingNotification(notification: notification, startedTyping: false)
    }

    func didReceiveParticipantJoin(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String,
              let sessionId = notification.userInfo?["sessionId"] as? String,
              token == self.room.token
        else { return }

        DispatchQueue.main.async {
            if self.isTyping {
                self.sendStartedTypingMessage(to: sessionId)
            }
        }
    }

    func didReceiveParticipantLeave(notification: Notification) {
        guard let token = notification.userInfo?["roomToken"] as? String,
              let sessionId = notification.userInfo?["sessionId"] as? String,
              token == self.room.token
        else { return }

        // For guests we use the sessionId as an identifier, for users we use the userId
        var userIdentifier = sessionId

        if let userId = notification.userInfo?["userId"] as? String, !userId.isEmpty {
            userIdentifier = userId
        }

        self.removeTypingIndicator(withUserIdentifier: userIdentifier)
    }

    // MARK: - Lobby functions

    func startObservingRoomLobbyFlag() {
        self.updateRoomInformation()

        DispatchQueue.main.async {
            self.lobbyCheckTimer?.invalidate()
            self.lobbyCheckTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(self.updateRoomInformation), userInfo: nil, repeats: true)
        }
    }

    func updateRoomInformation() {
        NCRoomsManager.sharedInstance().updateRoom(self.room.token, withCompletionBlock: nil)
    }

    func shouldPresentLobbyView() -> Bool {
        let serverSupportsConversationPermissions =
        NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityConversationPermissions, for: room) ||
        NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityDirectMentionFlag, for: room)

        if serverSupportsConversationPermissions, self.room.permissions.contains(.canIgnoreLobby) {
            return false
        }

        return self.room.lobbyState == .moderatorsOnly && !self.room.canModerate
    }

    // MARK: - Chat functions

    func couldRetrieveHistory() -> Bool {
        return self.hasReceiveInitialHistory &&
                !self.retrievingHistory &&
                !self.dateSections.isEmpty
                && self.hasStoredHistory
    }

    func checkLastCommonReadMessage() {
        DispatchQueue.main.async {
            guard let tableView = self.tableView,
                  let indexPathsForVisibleRows = tableView.indexPathsForVisibleRows
            else { return }

            var reloadCells: [IndexPath] = []

            for visibleIndexPath in indexPathsForVisibleRows {
                if let message = self.message(for: visibleIndexPath),
                   message.messageId > 0,
                   message.messageId <= self.room.lastCommonReadMessage {

                    reloadCells.append(visibleIndexPath)
                }
            }

            if !reloadCells.isEmpty {
                self.tableView?.beginUpdates()
                self.tableView?.reloadRows(at: reloadCells, with: .none)
                self.tableView?.endUpdates()
            }
        }
    }

    func checkForNewStoredMessages() {
        // Get the last "real" message. For temporary messages the messageId would be 0
        // which would load all stored messages of the current conversation
        if let lastMessage = self.getLastRealMessage()?.message {
            self.chatController.checkForNewMessages(fromMessageId: lastMessage.messageId)
            self.checkLastCommonReadMessage()
        }
    }

    // MARK: - Editing support

    public override func didCommitTextEditing(_ sender: Any) {
        if let editingMessage {
            let messageParametersJSONString = NCMessageParameter.messageParametersJSONString(from: self.mentionsDict) ?? ""
            editingMessage.message = self.replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: self.textView.text, parameters: messageParametersJSONString)
            editingMessage.messageParametersJSONString = messageParametersJSONString

            NCAPIController.sharedInstance().editChatMessage(inRoom: editingMessage.token, withMessageId: editingMessage.messageId, withMessage: editingMessage.sendingMessage, for: account) { messageDict, error, _ in
                if error != nil {
                    NotificationPresenter.shared().present(text: NSLocalizedString("Error occurred while editing a message", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                    return
                }

                guard let messageDict,
                      let parent = messageDict["parent"] as? [AnyHashable: Any],
                      let updatedMessage = NCChatMessage(dictionary: parent, andAccountId: self.account.accountId)
                else { return }

                self.updateMessage(withMessageId: editingMessage.messageId, updatedMessage: updatedMessage)
            }
        }

        super.didCommitTextEditing(sender)
    }

    // MARK: - ChatMessageTableViewCellDelegate delegate

    override public func cellDidSelectedReaction(_ reaction: NCChatReaction!, for message: NCChatMessage) {
        self.addOrRemoveReaction(reaction: reaction, in: message)
    }

    // MARK: - MessageSeparatorTableViewCellDelegate

    override func generateSummaryButtonPressed() {
        guard self.indexPathForUnreadMessageSeparator() != nil, let generateSummaryFromMessageId else { return }

        self.generateSummary(fromMessageId: generateSummaryFromMessageId)
        self.showGeneratingSummaryNotification()
    }

    func showGeneratingSummaryNotification() {
        NotificationPresenter.shared().present(title: NSLocalizedString("Generating summary of unread messages", comment: ""), subtitle: NSLocalizedString("This might take a moment", comment: ""), includedStyle: .dark)
        NotificationPresenter.shared().displayActivityIndicator(true)
    }

    func generateSummary(fromMessageId messageId: Int) {
        NCAPIController.sharedInstance().summarizeChat(forAccountId: self.room.accountId, inRoom: self.room.token, fromMessageId: messageId) { status, taskId, nextOffset in
            if status == .noAiProvider {
                NotificationPresenter.shared().present(text: NSLocalizedString("No AI provider available or summarizing failed", comment: ""), dismissAfterDelay: 7.0, includedStyle: .error)
                return
            }

            guard let taskId, status != .failed else {
                NotificationPresenter.shared().present(text: NSLocalizedString("Generating summary of unread messages failed", comment: ""), dismissAfterDelay: 7.0, includedStyle: .error)
                return
            }

            let hasRunningAiSummaryTasks = !AiSummaryController.shared.getSummaryTaskIds(forRoomInternalId: self.room.internalId).isEmpty

            // No messages to summarize found, no previous tasks running and no more messages -> Nothing we can do, stop here
            if status == .noMessagesFound, !hasRunningAiSummaryTasks, nextOffset == nil {
                NotificationPresenter.shared().present(text: NSLocalizedString("No messages found to summarize", comment: ""), dismissAfterDelay: 7.0, includedStyle: .error)
                return
            }

            // We might end up here with a status of "noMessagesFound". That can happen if we have previous running tasks, or got a nextOffset.
            // Therefore we explictly check for "success" to only track tasks that were successfully submitted with messages
            if status == .success {
                AiSummaryController.shared.addSummaryTaskId(forRoomInternalId: self.room.internalId, withTaskId: taskId)
                print("Scheduled summary task with taskId \(taskId) and nextOffset \(String(describing: nextOffset))")
            }

            // Add a safe-guard to make sure there's really a nextOffset. Otherwise we might end up requesting the same task over and over again
            if let nextOffset, nextOffset > messageId {
                // We were not able to get a summary of all messages at once, so we need to create another summary task
                self.generateSummary(fromMessageId: nextOffset)
            } else {
                // There's no offset anymore (or there never was one) so we start checking the task states
                self.scheduleSummaryTaskCheck()
            }
        }
    }

    func scheduleSummaryTaskCheck() {
        self.generateSummaryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false, block: { [weak self] _ in
            guard
                let self,
                let firstTaskId = AiSummaryController.shared.getSummaryTaskIds(forRoomInternalId: self.room.internalId).first
            else { return }

            NCAPIController.sharedInstance().getAiTaskById(for: self.room.accountId, withTaskId: firstTaskId) { [weak self] status, output in
                guard let self else { return }

                if status == .successful {
                    let resultOutput = output ?? NSLocalizedString("Empty summary response", comment: "")
                    AiSummaryController.shared.markSummaryTaskAsDone(forRoomInternalId: self.room.internalId, withTaskId: firstTaskId, withOutput: resultOutput)

                    if AiSummaryController.shared.getSummaryTaskIds(forRoomInternalId: self.room.internalId).isEmpty {
                        // No more taskIds to check -> show the summary
                        NotificationPresenter.shared().dismiss()

                        let outputs = AiSummaryController.shared.finalizeSummaryTask(forRoomInternalId: self.room.internalId)
                        let summaryVC = AiSummaryViewController(summaryText: outputs.joined(separator: "\n\n---\n\n"))
                        let navController = UINavigationController(rootViewController: summaryVC)
                        self.present(navController, animated: true)

                        return
                    }

                } else if status == .failed {
                    AiSummaryController.shared.finalizeSummaryTask(forRoomInternalId: self.room.internalId)
                    NotificationPresenter.shared().dismiss()
                    NotificationPresenter.shared().present(text: NSLocalizedString("Generating summary of unread messages failed", comment: ""), dismissAfterDelay: 7.0, includedStyle: .error)

                    return
                } else if status == .cancelled {
                    AiSummaryController.shared.finalizeSummaryTask(forRoomInternalId: self.room.internalId)
                    NotificationPresenter.shared().dismiss()
                    return
                }

                self.scheduleSummaryTaskCheck()
            }
        })
    }

    // MARK: - ContextMenu (Long press on message)

    func isMessageReplyable(message: NCChatMessage) -> Bool {
        return message.isReplyable && !message.isDeleting
    }

    func isMessageReactable(message: NCChatMessage) -> Bool {
        var isReactable = NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityReactions, for: room)
        isReactable = isReactable && !self.offlineMode
        isReactable = isReactable && self.room.readOnlyState != .readOnly
        isReactable = isReactable && !message.isDeletedMessage && !message.isCommandMessage && !message.sendingFailed && !message.isTemporary

        return isReactable
    }

    func getSetReminderOptions(for message: NCChatMessage) -> [UIMenuElement] {
        var reminderOptions: [UIMenuElement] = []
        let now = Date()

        let sunday = 1
        let monday = 2
        let friday = 6
        let saturday = 7

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        let setReminderCompletion: SetReminderForMessage = { (error: Error?) in
            if error != nil {
                NotificationPresenter.shared().present(text: NSLocalizedString("Error occurred when creating a reminder", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            } else {
                NotificationPresenter.shared().present(text: NSLocalizedString("Reminder was successfully set", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
            }
        }

        // Today
        let laterTodayTime = NCUtils.today(withHour: 18, withMinute: 0, withSecond: 0)!
        let laterToday = UIAction(title: NSLocalizedString("Later today", comment: "Remind me later today about that message"), subtitle: NCUtils.getTime(fromDate: laterTodayTime)) { _ in
            let timestamp = String(Int(laterTodayTime.timeIntervalSince1970))
            NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
        }

        // Tomorrow
        var tomorrowTime = NCUtils.today(withHour: 8, withMinute: 0, withSecond: 0)!
        tomorrowTime = Calendar.current.date(byAdding: .day, value: 1, to: tomorrowTime)!
        let tomorrow = UIAction(title: NSLocalizedString("Tomorrow", comment: "Remind me tomorrow about that message")) { _ in
            let timestamp = String(Int(tomorrowTime.timeIntervalSince1970))
            NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
        }
        tomorrow.subtitle = "\(formatter.string(from: tomorrowTime)), \(NCUtils.getTime(fromDate: tomorrowTime))"

        // This weekend
        var weekendTime = NCUtils.today(withHour: 8, withMinute: 0, withSecond: 0)!
        weekendTime = NCUtils.setWeekday(saturday, withDate: weekendTime)
        let thisWeekend = UIAction(title: NSLocalizedString("This weekend", comment: "Remind me this weekend about that message")) { _ in
            let timestamp = String(Int(weekendTime.timeIntervalSince1970))
            NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
        }
        thisWeekend.subtitle = "\(formatter.string(from: weekendTime)), \(NCUtils.getTime(fromDate: weekendTime))"

        // Next week
        var nextWeekTime = NCUtils.today(withHour: 8, withMinute: 0, withSecond: 0)!
        nextWeekTime = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: nextWeekTime)!
        nextWeekTime = NCUtils.setWeekday(monday, withDate: nextWeekTime)
        let nextWeek = UIAction(title: NSLocalizedString("Next week", comment: "Remind me next week about that message")) { _ in
            let timestamp = String(Int(nextWeekTime.timeIntervalSince1970))
            NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
        }
        nextWeek.subtitle = "\(formatter.string(from: nextWeekTime)), \(NCUtils.getTime(fromDate: nextWeekTime))"

        // Custom reminder
        let customReminderAction = UIAction(title: NSLocalizedString("Pick date & time", comment: ""), image: .init(systemName: "calendar.badge.clock")) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.interactingMessage = message
                self.lastMessageBeforeInteraction = self.tableView?.indexPathsForVisibleRows?.last

                let startingDate = Calendar.current.date(byAdding: .hour, value: 1, to: now)
                let minimumDate = Calendar.current.date(byAdding: .minute, value: 15, to: now)

                self.datePickerTextField.setupDatePicker(startingDate: startingDate, minimumDate: minimumDate)
                self.datePickerTextField.getDate { buttonTapped, selectedDate in
                    guard buttonTapped == .done, let selectedDate else { return }

                    let timestamp = String(Int(selectedDate.timeIntervalSince1970))
                    NCAPIController.sharedInstance().setReminderFor(message, withTimestamp: timestamp, withCompletionBlock: setReminderCompletion)
                }
            }
        }

        let customReminder = UIMenu(options: .displayInline, children: [customReminderAction])

        // Hide "Later today" when it's past 5pm
        if Calendar.current.component(.hour, from: now) < 17 {
            reminderOptions.append(laterToday)
        }

        reminderOptions.append(tomorrow)

        // Only show "This weekend" for Mon-Tue
        let nowWeekday = Calendar.current.component(.weekday, from: now)
        if nowWeekday != friday && nowWeekday != saturday && nowWeekday != sunday {
            reminderOptions.append(thisWeekend)
        }

        // "Next week" should be hidden on sunday
        if nowWeekday != sunday {
            reminderOptions.append(nextWeek)
        }

        reminderOptions.append(customReminder)

        return reminderOptions
    }

    override func getContextMenuAccessoryView(forMessage message: NCChatMessage, forIndexPath indexPath: IndexPath, withCellHeight cellHeight: CGFloat) -> UIView? {
        let hasChatPermissions = !NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityChatPermission, for: room) || self.room.permissions.contains(.chat)

        guard hasChatPermissions && self.isMessageReactable(message: message) else { return nil }

        let reactionViewPadding = 10
        let emojiButtonPadding = 10
        let emojiButtonSize = 48
        let frequentlyUsedEmojis = NCDatabaseManager.sharedInstance().activeAccount().frequentlyUsedEmojis

        let totalEmojiButtonWidth = frequentlyUsedEmojis.count * emojiButtonSize
        let totalEmojiButtonPadding = frequentlyUsedEmojis.count * emojiButtonPadding
        let addButtonWidth = emojiButtonSize + emojiButtonPadding

        // We need to add an extra padding to the right so the buttons are correctly padded
        let reactionViewWidth = totalEmojiButtonWidth + totalEmojiButtonPadding + addButtonWidth + emojiButtonPadding
        let reactionView = UIView(frame: .init(x: 0, y: Int(cellHeight) + reactionViewPadding, width: reactionViewWidth, height: emojiButtonSize))

        var positionX = emojiButtonPadding

        for emoji in frequentlyUsedEmojis {
            let emojiShortcutButton = UIButton(type: .system)
            emojiShortcutButton.frame = CGRect(x: positionX, y: 0, width: emojiButtonSize, height: emojiButtonSize)
            emojiShortcutButton.layer.cornerRadius = CGFloat(emojiButtonSize) / 2

            emojiShortcutButton.titleLabel?.font = .systemFont(ofSize: 20)
            emojiShortcutButton.setTitle(emoji, for: .normal)
            emojiShortcutButton.backgroundColor = .systemBackground

            emojiShortcutButton.addAction { [weak self] in
                guard let self else { return }
                self.tableView?.contextMenuInteraction?.dismissMenu()

                self.contextMenuActionBlock = {
                    self.addReaction(reaction: emoji, to: message)
                }
            }

            // Disable shortcuts, if we already reacted with that emoji
            for reaction in message.reactionsArray() {
                if reaction.reaction == emoji && reaction.userReacted {
                    emojiShortcutButton.isEnabled = false
                    emojiShortcutButton.alpha = 0.4
                    break
                }
            }

            reactionView.addSubview(emojiShortcutButton)
            positionX += emojiButtonSize + emojiButtonPadding
        }

        let addReactionButton = UIButton(type: .system)
        addReactionButton.frame = CGRect(x: positionX, y: 0, width: emojiButtonSize, height: emojiButtonSize)
        addReactionButton.layer.cornerRadius = CGFloat(emojiButtonSize) / 2

        addReactionButton.titleLabel?.font = .systemFont(ofSize: 22)
        addReactionButton.setImage(.init(systemName: "plus"), for: .normal)
        addReactionButton.tintColor = .label
        addReactionButton.backgroundColor = .systemBackground
        addReactionButton.addAction { [weak self] in
            guard let self else { return }
            self.tableView?.contextMenuInteraction?.dismissMenu()

            self.contextMenuActionBlock = {
                self.didPressAddReaction(for: message, at: indexPath)
            }
        }

        reactionView.addSubview(addReactionButton)

        // The reactionView will be shown after the animation finishes, otherwise we see the view already when animating and this looks odd
        reactionView.alpha = 0
        reactionView.layer.cornerRadius = CGFloat(emojiButtonSize) / 2
        reactionView.backgroundColor = .systemBackground

        return reactionView
    }

    // swiftlint:disable:next cyclomatic_complexity
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

        guard let message = self.message(for: indexPath)
        else { return nil }

        if message.isSystemMessage || message.isDeletedMessage ||
            message.messageId == MessageSeparatorTableViewCell.unreadMessagesSeparatorId ||
            message.messageId == MessageSeparatorTableViewCell.unreadMessagesWithSummarySeparatorId ||
            message.messageId == MessageSeparatorTableViewCell.chatBlockSeparatorId {

            return nil
        }

        var actions: [UIMenuElement] = []
        var informationalActions: [UIMenuElement] = []
        let hasChatPermissions = !NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityChatPermission, for: room) || self.room.permissions.contains(.chat)

        // Show edit information
        if let lastEditActorDisplayName = message.lastEditActorDisplayName, message.lastEditTimestamp > 0 {
            let timestampDate = Date(timeIntervalSince1970: TimeInterval(message.lastEditTimestamp))

            let editInfo = UIAction(title: NSLocalizedString("Edited by", comment: "A message was edited by ...") + " " + lastEditActorDisplayName, attributes: [.disabled], handler: {_ in })
            editInfo.subtitle = NCUtils.readableTimeAndDate(fromDate: timestampDate)

            informationalActions.append(editInfo)
        }

        // Show silent send information
        if message.isSilent {
            let silentInfo = UIAction(title: NSLocalizedString("Sent without notification", comment: "A message has been sent without notifications"), attributes: [.disabled], handler: {_ in })
            silentInfo.image = UIImage(systemName: "bell.slash")

            informationalActions.append(silentInfo)
        }

        if !informationalActions.isEmpty {
            actions.append(UIMenu(options: [.displayInline], children: informationalActions))
        }

        // Reply option
        if self.isMessageReplyable(message: message), hasChatPermissions, !self.textInputbar.isEditing {
            actions.append(UIAction(title: NSLocalizedString("Reply", comment: ""), image: .init(systemName: "arrowshape.turn.up.left")) { _ in
                self.didPressReply(for: message)
            })
        }

        // Show "Add reaction" when running on MacOS because we don't have an accessory view
        if self.isMessageReactable(message: message), hasChatPermissions, NCUtils.isiOSAppOnMac() {
            actions.append(UIAction(title: NSLocalizedString("Add reaction", comment: ""), image: .init(systemName: "face.smiling")) { _ in
                self.didPressAddReaction(for: message, at: indexPath)
            })
        }

        // Forward option (only normal messages for now)
        if message.file() == nil, message.poll == nil, !message.isDeletedMessage {
            actions.append(UIAction(title: NSLocalizedString("Forward", comment: ""), image: .init(systemName: "arrowshape.turn.up.right")) { _ in
                self.didPressForward(for: message)
            })
        }

        var copyMenuActions: [UIMenuElement] = []

        // Copy option
        copyMenuActions.append(UIAction(title: NSLocalizedString("Message", comment: "Copy 'message'"), image: .init(systemName: "doc.text")) { _ in
            self.didPressCopy(for: message)
        })

        // Copy part option
        copyMenuActions.append(UIAction(title: NSLocalizedString("Selection", comment: "Copy a 'selection' of a message"), image: .init(systemName: "text.viewfinder")) { _ in
            self.didPressCopySelection(for: message)
        })

        // Copy link option
        copyMenuActions.append(UIAction(title: NSLocalizedString("Message link", comment: "Copy 'link' to a message"), image: .init(systemName: "link")) { _ in
            self.didPressCopyLink(for: message)
        })

        actions.append(UIMenu(title: NSLocalizedString("Copy", comment: ""), image: .init(systemName: "doc.on.doc"), children: copyMenuActions))

        // Remind me later
        if !message.sendingFailed, !message.isOfflineMessage, NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityRemindMeLater, for: room) {
            let deferredMenuElement = UIDeferredMenuElement.uncached { [weak self] completion in
                NCAPIController.sharedInstance().getReminderFor(message) { [weak self] response, error in
                    guard let self else { return }

                    var menuOptions: [UIMenuElement] = []
                    menuOptions.append(contentsOf: self.getSetReminderOptions(for: message))

                    if error == nil,
                       let responseDict = response as? [String: Any],
                       let timestamp = responseDict["timestamp"] as? Int {

                        // There's already an existing reminder set for this message
                        // -> offer a delete option
                        let timestampDate = Date(timeIntervalSince1970: TimeInterval(timestamp))

                        let clearAction = UIAction(title: NSLocalizedString("Clear reminder", comment: ""), image: .init(systemName: "trash")) { _ in
                            NCAPIController.sharedInstance().deleteReminder(for: message) { error in
                                if error == nil {
                                    NotificationPresenter.shared().present(text: NSLocalizedString("Reminder was successfully cleared", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                                } else {
                                    NotificationPresenter.shared().present(text: NSLocalizedString("Failed to clear reminder", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                                }
                            }
                        }
                        clearAction.subtitle = NCUtils.readableDateTime(fromDate: timestampDate)
                        clearAction.attributes = .destructive

                        menuOptions.append(UIMenu(options: .displayInline, children: [clearAction]))
                    }

                    completion(menuOptions)
                }
            }

            actions.append(UIMenu(title: NSLocalizedString("Set reminder", comment: "Remind me later about that message"),
                                  image: .init(systemName: "alarm"),
                                  children: [deferredMenuElement]))
        }

        // Re-send option
        if (message.sendingFailed || message.isOfflineMessage) && hasChatPermissions {
            actions.append(UIAction(title: NSLocalizedString("Resend", comment: ""), image: .init(systemName: "arrow.clockwise")) { _ in
                self.didPressResend(for: message)
            })
        }

        // Open in nextcloud option
        if !self.offlineMode, message.file() != nil {
            let openInNextcloudTitle = String(format: NSLocalizedString("Open in %@", comment: ""), filesAppName)
            actions.append(UIAction(title: openInNextcloudTitle, image: .init(named: "logo-action")?.withRenderingMode(.alwaysTemplate)) { _ in
                self.didPressOpenInNextcloud(for: message)
            })
        }

        // Transcribe voice-message
        if message.messageType == kMessageTypeVoiceMessage {
            let transcribeTitle = NSLocalizedString("Transcribe", comment: "TRANSLATORS this is for transcribing a voice message to text")
            actions.append(UIAction(title: transcribeTitle, image: .init(systemName: "text.bubble")) { _ in
                self.didPressTranscribeVoiceMessage(for: message)
            })
        }

        var moreMenuActions: [UIMenuElement] = []

        // Reply-privately option (only to other users and not in one-to-one)
        if self.isMessageReplyable(message: message), self.room.type != .oneToOne, message.actorType == "users", message.actorId != self.account.userId {
            moreMenuActions.append(UIAction(title: NSLocalizedString("Reply privately", comment: ""), image: .init(systemName: "person")) { _ in
                self.didPressReplyPrivately(for: message)
            })
        }

        // Translate
        if !self.offlineMode, NCDatabaseManager.sharedInstance().hasAvailableTranslations(forAccountId: self.account.accountId) {
            moreMenuActions.append(UIAction(title: NSLocalizedString("Translate", comment: ""), image: .init(systemName: "character.book.closed")) { _ in
                self.didPressTranslate(for: message)
            })
        }

        // Note to self
        if message.file() == nil, message.poll == nil, !message.isDeletedMessage, room.type != .noteToSelf,
           NCDatabaseManager.sharedInstance().roomHasTalkCapability(kCapabilityNoteToSelf, for: room) {
            moreMenuActions.append(UIAction(title: NSLocalizedString("Note to self", comment: ""), image: .init(systemName: "square.and.pencil")) { _ in
                self.didPressNoteToSelf(for: message)
            })
        }

        if moreMenuActions.count == 1, let firstElement = moreMenuActions.first {
            // When there's only one element, no need to create a "More" menu
            actions.append(firstElement)
        } else if !moreMenuActions.isEmpty {
            actions.append(UIMenu(title: NSLocalizedString("More", comment: "More menu elements"), children: moreMenuActions))
        }

        var destructiveMenuActions: [UIMenuElement] = []

        // Edit option
        if message.isEditable(for: self.account, in: self.room) && hasChatPermissions {
            destructiveMenuActions.append(UIAction(title: NSLocalizedString("Edit", comment: "Edit a message or room participants"), image: .init(systemName: "pencil")) { _ in
                self.didPressEdit(for: message)
            })
        }

        // Delete option
        if message.sendingFailed || message.isOfflineMessage || (message.isDeletable(for: self.account, in: self.room) && hasChatPermissions) {
            destructiveMenuActions.append(UIAction(title: NSLocalizedString("Delete", comment: ""), image: .init(systemName: "trash"), attributes: .destructive) { _ in
                self.didPressDelete(for: message)
            })
        }

        if !destructiveMenuActions.isEmpty {
            actions.append(UIMenu(options: [.displayInline], children: destructiveMenuActions))
        }

        let menu = UIMenu(children: actions)

        let configuration = UIContextMenuConfiguration(identifier: indexPath as NSIndexPath) {
            return nil
        } actionProvider: { _ in
            return menu
        }

        return configuration
    }

    // MARK: - NCChatTitleViewDelegate

    public override func chatTitleViewTapped(_ titleView: NCChatTitleView!) {
        let roomInfo = RoomInfoUIViewFactory.create(room: self.room, showDestructiveActions: !self.presentedInCall)

        if let splitViewController = NCUserInterfaceController.sharedInstance().mainViewController, !splitViewController.isCollapsed {
            let cancelButton = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { _ in
                roomInfo.dismiss(animated: true)
            })

            if #unavailable(iOS 26.0) {
                cancelButton.tintColor = NCAppBranding.themeTextColor()
            }
            
            roomInfo.modalPresentationStyle = .pageSheet

            let navController = UINavigationController(rootViewController: roomInfo)
            navController.navigationBar.topItem?.leftBarButtonItem = cancelButton
            self.present(navController, animated: true)
        } else {
            self.navigationController?.pushViewController(roomInfo, animated: true)
        }

        // When returning from RoomInfoTableViewController the default keyboard will be shown, so the height might be wrong -> make sure the keyboard is hidden
        self.dismissKeyboard(true)
    }

    // MARK: - Presentation controller delegate

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.leaveChat()
    }

    public func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        // Allow swipe down to dismiss
        return true
    }
}
