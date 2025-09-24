//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import ReplayKit
import WebRTC
import MetalKit
import AVKit

@objc protocol CallViewControllerDelegate {
    @objc func callViewControllerWantsToBeDismissed(_ viewController: CallViewController)
    @objc func callViewControllerWantsVideoCallUpgrade(_ viewController: CallViewController)
    @objc func callViewControllerDidFinish(_ viewController: CallViewController)
    @objc func callViewController(_ viewController: CallViewController, wantsToSwitchFromRoom from: String, toRoom to: String)
}

enum CallViewSection {
    case main
}

@objcMembers
class CallViewController: UIViewController,
                            NCCallControllerDelegate,
                            UICollectionViewDelegate,
                            UICollectionViewDelegateFlowLayout,
                            RTCVideoViewDelegate,
                            CallParticipantViewCellDelegate,
                            UIGestureRecognizerDelegate,
                            NCChatTitleViewDelegate {

    class PendingCellUpdate: NSObject {
        public var peer: NCPeerConnection
        public var block: (CallParticipantViewCell) -> Void

        init(peer: NCPeerConnection, block: @escaping (CallParticipantViewCell) -> Void) {
            self.peer = peer
            self.block = block
        }
    }

    public weak var delegate: CallViewControllerDelegate?

    public var room: NCRoom
    public var audioDisabledAtStart = false
    public var videoDisabledAtStart = false
    public var voiceChatModeAtStart = false
    public var initiator = false
    public var silentCall = false
    public var recordingConsent = false

    private var speakers: [NCPeerConnection] = []

    @IBOutlet public var localVideoView: MTKView!
    @IBOutlet public var localVideoViewWrapper: UIView!
    @IBOutlet public var screensharingView: NCZoomableView!
    @IBOutlet public var closeScreensharingButton: UIButton!
    @IBOutlet public var toggleChatButton: UIButton!
    @IBOutlet public var waitingView: UIView!
    @IBOutlet public var waitingLabel: UILabel!
    @IBOutlet public var avatarBackgroundImageView: AvatarBackgroundImageView!
    @IBOutlet public var titleView: NCChatTitleView!
    @IBOutlet public var callTimeLabel: UILabel!
    @IBOutlet public var screenshareLabelContainer: UIView!
    @IBOutlet public var screenshareLabel: UILabel!
    @IBOutlet public var participantsLabelContainer: UIView!
    @IBOutlet public var participantsLabel: UILabel!

    @IBOutlet private var collectionViewLeftConstraint: NSLayoutConstraint!
    @IBOutlet private var collectionViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet private var collectionViewRightConstraint: NSLayoutConstraint!
    @IBOutlet private var topBarViewRightContraint: NSLayoutConstraint!
    @IBOutlet private var screenshareViewRightContraint: NSLayoutConstraint!
    @IBOutlet private var sideBarViewRightConstraint: NSLayoutConstraint!
    @IBOutlet private var sideBarViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet private var sideBarWidthConstraint: NSLayoutConstraint!
    @IBOutlet private var stackViewToTitleViewConstraint: NSLayoutConstraint!

    @IBOutlet private var audioMuteButton: UIButton!
    @IBOutlet private var speakerButton: UIButton!
    @IBOutlet private var videoDisableButton: UIButton!
    @IBOutlet private var switchCameraButton: UIButton!
    @IBOutlet private var hangUpButton: UIButton!
    @IBOutlet private var videoCallButton: UIButton!
    @IBOutlet private var recordingButton: UIButton!
    @IBOutlet private var lowerHandButton: UIButton!
    @IBOutlet private var moreMenuButton: UIButton!
    @IBOutlet private var collectionView: UICollectionView!
    @IBOutlet private var topBarView: UIView!
    @IBOutlet private var topBarButtonStackView: UIStackView!
    @IBOutlet private var sideBarView: UIView!

    private let sidebarWidth = 350.0
    private let reactionViewAnimationDuration = 2.0
    private let reactionViewHidingDuration = 1.0
    private let maxReactionsOnScreen = 5.0

    private var localVideoOriginPosition: CGPoint = .zero
    private var peersInCall: [NCPeerConnection] = []
    private var screenPeersInCall: [NCPeerConnection] = []
    private var videoRenderersDict: [String: RTCMTLVideoView] = [:] // peerIdentifier -> renderer
    private var screenRenderersDict: [String: RTCMTLVideoView] = [:] // peerId -> renderer
    private var presentedScreenPeerId: String?
    private var callController: NCCallController?
    private var chatViewController: ChatViewController?
    private var chatNavigationController: UINavigationController?
    private var screensharingSize: CGSize?
    private var tapGestureForDetailedView: UITapGestureRecognizer?
    private var detailedViewTimer: Timer?
    private var proximityTimer: Timer?
    private var displayName: String?
    private var isAudioOnly = false
    private var isDetailedViewVisible = false
    private var userDisabledVideo = false
    private var userDisabledSpeaker = false
    private var videoCallUpgrade = false
    private var hangingUp = false
    private var pushToTalkActive = false
    private var isHandRaised = false
    private var proximityState = false
    private var showChatAfterRoomSwitch = false
    private var connectingSoundAlreadyPlayed = false
    private var buttonFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var localVideoDragStartingPoint: CGPoint?
    private var airplayView = AVRoutePickerView(frame: .init(x: 0, y: 0, width: 48, height: 56))
    private var pendingPeerInserts: [NCPeerConnection] = []
    private var pendingPeerDeletions: [NCPeerConnection] = []
    private var pendingPeerUpdates: [PendingCellUpdate] = []
    private var batchUpdateTimer: Timer?
    private var barButtonsConfiguration = UIImage.SymbolConfiguration(pointSize: 20)
    private var lastScheduledReaction: CGFloat = 0
    private var callDurationTimer: Timer?
    private var soundsPlayer: AVAudioPlayer?
    private var currentCallState: CallState = .joining
    private var previousParticipants: [String] = []

    public init?(for room: NCRoom, asUser displayName: String, audioOnly: Bool) {
        self.room = room
        self.displayName = displayName
        self.isAudioOnly = audioOnly

        super.init(nibName: "CallViewController", bundle: nil)

        self.modalPresentationStyle = .fullScreen

        NotificationCenter.default.addObserver(self, selector: #selector(didJoinRoom(notification:)), name: NSNotification.Name.NCRoomsManagerDidJoinRoom, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(providerDidEndCall(notification:)), name: NSNotification.Name.CallKitManagerDidEndCall, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(providerDidChangeAudioMute(notification:)), name: NSNotification.Name.CallKitManagerDidChangeAudioMute, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(providerWantsToUpgradeToVideoCall(notification:)), name: NSNotification.Name.CallKitManagerWantsToUpgradeToVideoCall, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionDidChangeRoute(notification:)), name: NSNotification.Name.AudioSessionDidChangeRoute, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionDidActivate(notification:)), name: NSNotification.Name.AudioSessionWasActivatedByProvider, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionDidChangeRoutingInformation(notification:)), name: NSNotification.Name.AudioSessionDidChangeRoutingInformation, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(notification:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive(notification:)), name: UIApplication.willResignActiveNotification, object: nil)

        AllocationTracker.shared.addAllocation("CallViewController")
    }

    deinit {
        AllocationTracker.shared.removeAllocation("CallViewController")
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startCall(withSessionId sessionId: String) {
        let callController = NCCallController(delegate: self, in: self.room, forAudioOnlyCall: self.isAudioOnly, withSessionId: sessionId, andVoiceChatMode: self.voiceChatModeAtStart)
        self.callController = callController

        callController.userDisplayName = self.displayName
        callController.disableAudioAtStart = self.audioDisabledAtStart
        callController.disableVideoAtStart = self.videoDisabledAtStart
        callController.silentCall = self.silentCall
        callController.recordingConsent = self.recordingConsent

        // Check if there are previous participants and we are joning an extended room
        if self.room.objectType == NCRoomObjectTypeExtendedConversation {
            callController.silentCall = false
            if !self.previousParticipants.isEmpty {
                callController.silentFor = previousParticipants
            }
        }

        callController.startCall()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setCallState(.joining)

        self.tapGestureForDetailedView = UITapGestureRecognizer(target: self, action: #selector(showDetailedViewWithTimer))
        self.tapGestureForDetailedView?.numberOfTapsRequired = 1

        let pushToTalkRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handlePushToTalk))
        self.audioMuteButton.addGestureRecognizer(pushToTalkRecognizer)

        self.participantsLabelContainer.isHidden = true

        self.screensharingView.isHidden = true
        self.screensharingView.clipsToBounds = true

        self.hangUpButton.layer.cornerRadius = self.hangUpButton.frame.height / 2
        self.closeScreensharingButton.layer.cornerRadius = 16

        self.collectionView.layer.cornerRadius = 22
        self.collectionView.contentInsetAdjustmentBehavior = .always

        self.sideBarView.clipsToBounds = true
        self.sideBarView.layer.cornerRadius = 22

        self.airplayView.tintColor = .white
        self.airplayView.activeTintColor = .white

        self.audioMuteButton.accessibilityLabel = NSLocalizedString("Microphone", comment: "")
        self.audioMuteButton.accessibilityValue = NSLocalizedString("Microphone enabled", comment: "")
        self.audioMuteButton.accessibilityHint = NSLocalizedString("Double tap to enable or disable the microphone", comment: "")
        self.speakerButton.accessibilityLabel = NSLocalizedString("Speaker", comment: "speaker = Loudspeaker, device")
        self.speakerButton.accessibilityValue = NSLocalizedString("Speaker disabled", comment: "speaker = Loudspeaker, device")
        self.speakerButton.accessibilityHint = NSLocalizedString("Double tap to enable or disable the speaker", comment: "speaker = Loudspeaker, device")
        self.videoDisableButton.accessibilityLabel = NSLocalizedString("Camera", comment: "")
        self.videoDisableButton.accessibilityValue = NSLocalizedString("Camera enabled", comment: "")
        self.videoDisableButton.accessibilityHint = NSLocalizedString("Double tap to enable or disable the camera", comment: "")
        self.hangUpButton.accessibilityLabel = NSLocalizedString("Hang up", comment: "")
        self.hangUpButton.accessibilityHint = NSLocalizedString("Double tap to hang up the call", comment: "")
        self.videoCallButton.accessibilityLabel = NSLocalizedString("Camera", comment: "")
        self.videoCallButton.accessibilityHint = NSLocalizedString("Double tap to upgrade this voice call to a video call", comment: "")
        self.toggleChatButton.accessibilityLabel = NSLocalizedString("Chat", comment: "")
        self.toggleChatButton.accessibilityHint = NSLocalizedString("Double tap to show or hide chat view", comment: "")
        self.toggleChatButton.accessibilityIdentifier = "toggleChatButton"
        self.recordingButton.accessibilityLabel = NSLocalizedString("Recording", comment: "")
        self.recordingButton.accessibilityHint = NSLocalizedString("Double tap to stop recording", comment: "")
        self.lowerHandButton.accessibilityLabel = NSLocalizedString("Lower hand", comment: "")
        self.lowerHandButton.accessibilityHint = NSLocalizedString("Double tap to lower hand", comment: "")
        self.moreMenuButton.accessibilityLabel = NSLocalizedString("More actions", comment: "")
        self.moreMenuButton.accessibilityHint = NSLocalizedString("Double tap to show more actions", comment: "")
        self.moreMenuButton.accessibilityIdentifier = "moreMenuButton"

        let deferredMoreMenu = UIDeferredMenuElement.uncached { [unowned self] completion in
            completion(self.getMoreButtonMenuItems())
        }

        self.moreMenuButton.showsMenuAsPrimaryAction = true
        self.moreMenuButton.menu = UIMenu(title: "", children: [deferredMoreMenu])

        // Text color should be always white in the call view
        self.titleView.titleTextColor = .white
        self.titleView.update(for: room)

        // The titleView uses the themeColor as a background for the userStatusImage
        // As we always have a black background, we need to change that
        self.titleView.userStatusBackgroundColor = .black

        self.titleView.delegate = self
        self.collectionView.delegate = self
        self.applyInitialSnapshot()

        self.createWaitingScreen()

        // We hide localVideoView until we receive it from cameraController
        self.setLocalVideoViewWrapperHidden(true)
        self.localVideoViewWrapper.layer.cornerRadius = 15
        self.localVideoViewWrapper.layer.masksToBounds = true

        // We disableLocalVideo here even if the call controller has not been created just to show the video button as disabled
        // also we set _userDisabledVideo = YES so the proximity sensor doesn't enable it.
        if self.videoDisabledAtStart {
            self.userDisabledVideo = true
            self.disableLocalVideo()
        }

        if self.voiceChatModeAtStart {
            self.userDisabledSpeaker = true
        }

        // 'conversation-permissions' capability was not added in Talk 13 release, so we check for 'direct-mention-flag' capability
        // as a workaround.

        let serverSupportsConversationPermissions =
        NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationPermissions, forAccountId: room.accountId) ||
        NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityDirectMentionFlag, forAccountId: room.accountId)

        if serverSupportsConversationPermissions {
            self.setAudioMuteButtonEnabled(room.permissions.contains(.canPublishAudio))
            self.setVideoDisableButtonEnabled(room.permissions.contains(.canPublishVideo))
        }

        self.collectionView.register(UINib(nibName: kCallParticipantCellNibName, bundle: nil), forCellWithReuseIdentifier: kCallParticipantCellIdentifier)
        self.collectionView.contentInsetAdjustmentBehavior = .never

        let localVideoDragGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(localVideoDragged(_:)))
        self.localVideoViewWrapper.addGestureRecognizer(localVideoDragGestureRecognizer)

        NotificationCenter.default.addObserver(self, selector: #selector(sensorStateChange(notification:)), name: UIDevice.proximityStateDidChangeNotification, object: nil)

        // callStartTime is only available if we have the "recording-v1" capability
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRecordingV1, forAccountId: room.accountId) {
            self.callDurationTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(callDurationTimerUpdate), userInfo: nil, repeats: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.screenshareLabelContainer.layer.cornerRadius = self.screenshareLabelContainer.frame.height / 2
        self.participantsLabelContainer.layer.cornerRadius = self.participantsLabelContainer.frame.height / 2
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        self.adjustConstraints()
        self.collectionView.collectionViewLayout.invalidateLayout()

        coordinator.animate { _ in
            self.setLocalVideoRect()
            self.screensharingView.resizeContentView()
            self.adjustTopBar()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        self.adjustConstraints()
        self.setLocalVideoRect()
        self.adjustTopBar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.setSideBarVisible(false, animated: false, withCompletion: nil)
        self.adjustConstraints()
        self.adjustSpeakerButton()
        self.adjustTopBar()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        UIDevice.current.isProximityMonitoringEnabled = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        UIDevice.current.isProximityMonitoringEnabled = true
        UIApplication.shared.isIdleTimerDisabled = true

        self.setLocalVideoRect()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Not push-to-talk while in caht
        if chatNavigationController == nil, presses.contains(where: { $0.key?.keyCode == .keyboardSpacebar }) {
            self.pushToTalkStart()
            return
        }

        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Not push-to-talk while in caht
        if chatNavigationController == nil, presses.contains(where: { $0.key?.keyCode == .keyboardSpacebar }) {
            self.pushToTalkEnd()
            return
        }

        super.pressesBegan(presses, with: event)
    }

    // MARK: - App lifecycle notifications

    func appDidBecomeActive(notification: NSNotification) {
        if callController != nil, !isAudioOnly, !userDisabledVideo {
            // Only enabled video if it was not disabled by the user
            self.enableLocalVideo()
        }
    }

    func appWillResignActive(notification: NSNotification) {
        if let callController, !isAudioOnly {
            callController.getVideoEnabledState { isEnabled in
                if isEnabled {
                    // Disable video when the app moves to the background as we can't access the camera anymore.
                    self.disableLocalVideo()
                }
            }
        }
    }

    // MARK: - Rooms manager notification

    func didJoinRoom(notification: NSNotification) {
        guard let token = notification.userInfo?["token"] as? String, token == self.room.token
        else { return }

        if let error = notification.userInfo?["error"] as? NSError, let reason = notification.userInfo?["errorReason"] as? String {
            self.presentJoinError(reason)
            return
        }

        if let roomController = notification.userInfo?["roomController"] as? NCRoomController, self.callController == nil {
            self.startCall(withSessionId: roomController.userSessionId)
        }

        self.titleView.update(for: room)
    }

    func providerDidChangeAudioMute(notification: NSNotification) {
        guard let token = notification.userInfo?["roomToken"] as? String, token == self.room.token
        else { return }

        if let isMuted = notification.userInfo?["isMuted"] as? Bool {
            self.setAudioMuted(isMuted)
        }
    }

    func providerDidEndCall(notification: NSNotification) {
        guard let token = notification.userInfo?["roomToken"] as? String, token == self.room.token
        else { return }

        self.hangup(forAll: (room.type == .oneToOne))
    }

    func providerWantsToUpgradeToVideoCall(notification: NSNotification) {
        guard let token = notification.userInfo?["roomToken"] as? String, token == self.room.token
        else { return }

        if isAudioOnly {
            self.showUpgradeToVideoCallDialog()
        }
    }

    // MARK: - Audio controller notifications

    func audioSessionDidChangeRoute(notification: NSNotification) {
        self.adjustSpeakerButton()
    }

    func audioSessionDidActivate(notification: NSNotification) {
        self.adjustSpeakerButton()
    }

    func audioSessionDidChangeRoutingInformation(notification: NSNotification) {
        self.adjustSpeakerButton()
    }

    // MARK: - Proximity sensor

    func sensorStateChange(notification: NSNotification) {
        DispatchQueue.main.async {
            self.proximityTimer?.invalidate()
            self.proximityTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.adjustProximityState), userInfo: nil, repeats: false)
        }
    }

    func adjustProximityState() {
        let currentProximityState = UIDevice.current.proximityState

        if currentProximityState == self.proximityState {
            return
        }

        self.proximityState = currentProximityState

        if !isAudioOnly {
            if proximityState {
                self.disableLocalVideo()
                self.disableSpeaker()

                self.localVideoOriginPosition = self.localVideoViewWrapper.frame.origin
                self.adjustLocalVideoPositionFromOriginPosition(localVideoOriginPosition)
            } else {
                // Only enable video if it was not disabled by the user
                if !userDisabledVideo {
                    self.enableLocalVideo()
                }

                if !userDisabledSpeaker {
                    self.enableSpeaker()
                }
            }
        }

        self.pushToTalkEnd()
    }

    // MARK: - CallParticipantViewCell delegate

    func cellWants(toPresentScreenSharing participantCell: CallParticipantViewCell!) {
        if let peerConnection = self.peerConnection(forPeerIdentifier: participantCell.peerIdentifier) {
            self.showScreenOfPeer(peerConnection)
        }
    }

    func cellWants(toChangeZoom participantCell: CallParticipantViewCell!, showOriginalSize: Bool) {
        if let peerConnection = self.peerConnection(forPeerIdentifier: participantCell.peerIdentifier) {
            peerConnection.showRemoteVideoInOriginalSize = showOriginalSize
        }
    }

    // MARK: - UICollectionView Datasource

    lazy var dataSource: UICollectionViewDiffableDataSource<CallViewSection, NCPeerConnection> = {
        return UICollectionViewDiffableDataSource<CallViewSection, NCPeerConnection>(collectionView: collectionView) { [weak self] collectionView, indexPath, peerConnection -> UICollectionViewCell? in

            guard let participantCell = collectionView.dequeueReusableCell(withReuseIdentifier: kCallParticipantCellIdentifier, for: indexPath) as? CallParticipantViewCell
            else { return UICollectionViewCell() }

            participantCell.peerIdentifier = peerConnection.peerIdentifier
            participantCell.actionsDelegate = self

            return participantCell
        }
    }()

    private func applyInitialSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<CallViewSection, NCPeerConnection>()
        snapshot.appendSections([.main])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func updateSnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<CallViewSection, NCPeerConnection>()
        snapshot.appendSections([.main])
        snapshot.appendItems(peersInCall)
        dataSource.apply(snapshot, animatingDifferences: true)

        self.setCallStateForPeersInCall()
    }

    func priority(for peerConnection: NCPeerConnection) -> (Int, Int) {
        // 1. Screen sharers
        if screenRenderersDict[peerConnection.peerId] != nil {
            return (0, peerConnection.addedTime)
        }

        // 2. Speakers (respecting order in speakers array)
        if let speakerIndex = speakers.firstIndex(of: peerConnection) {
            return (1, speakerIndex)
        }

        // 3. Peers sending audio/video streams
        if peerConnection.hasRemoteStream() {
            if !peerConnection.isRemoteVideoDisabled {
                return (2, peerConnection.addedTime)
            } else {
                return (3, peerConnection.addedTime)
            }
        }

        // 4. Other peers
        return (4, peerConnection.addedTime)
    }

    func sortPeersInCall() {
        // Only sort participants if the collection view is scrollable (not all participants fit in the screen)
        if collectionView.contentSize.height > collectionView.bounds.height {
            peersInCall.sort { priority(for: $0) < priority(for: $1) }
        }
    }

    func addSpeakerAndPromoteIfNeeded(_ peerConnection: NCPeerConnection) {
        DispatchQueue.main.async {
            let isVisible = self.collectionView.indexPathsForVisibleItems.contains {
                self.dataSource.itemIdentifier(for: $0)?.peerIdentifier == peerConnection.peerIdentifier
            }

            // Do not add to speakers or resort if participant is already visible.
            if isVisible { return }

            // If already in speakers and not visible, promote to the first position.
            // Skip reordering if already at the top.
            if let index = self.speakers.firstIndex(of: peerConnection) {
                guard index != 0 else { return }
                self.speakers.remove(at: index)
            }
            self.speakers.insert(peerConnection, at: 0)

            self.sortPeersInCall()
            self.updateSnapshot()
        }
    }

    func updateParticipantCell(cell: CallParticipantViewCell, withPeerConnection peerConnection: NCPeerConnection) {
        var isVideoDisabled = peerConnection.isRemoteVideoDisabled

        if isAudioOnly || !peerConnection.hasRemoteStream() {
            isVideoDisabled = true
        }

        if let videoView = videoRenderersDict[peerConnection.peerIdentifier] {
            cell.setVideoView(videoView)

            // It is possible that we receive a `didChangeVideoSize` call, while the participant cell was not yet shown,
            // therefore the remote video size will never be set. In case we have a videoView here, use the frame size
            let videoSize = videoView.frame.size
            let currentSize = cell.getRemoteVideoSize()

            // Only set it, when there's no size set yet
            if currentSize.equalTo(.zero), !videoSize.equalTo(.zero) {
                cell.setRemoteVideoSize(videoSize)
            }
        }

        cell.displayName = peerConnection.peerName
        cell.audioDisabled = peerConnection.isRemoteAudioDisabled
        cell.screenShared = screenRenderersDict[peerConnection.peerId] != nil
        cell.videoDisabled = isVideoDisabled
        cell.showOriginalSize = peerConnection.showRemoteVideoInOriginalSize
        cell.setRaiseHand(peerConnection.isHandRaised)
        cell.peerNameLabel.alpha = isDetailedViewVisible ? 1.0 : 0.0
        cell.audioOffIndicator.alpha = isDetailedViewVisible ? 1.0 : 0.0

        WebRTCCommon.shared.dispatch {
            let actor = self.callController?.getActorFromSessionId(peerConnection.peerId) ?? TalkActor()

            if actor.rawDisplayName.isEmpty, let peerName = peerConnection.peerName, !peerName.isEmpty {
                actor.rawDisplayName = peerName
            }

            let connectionState: RTCIceConnectionState = peerConnection.isDummyPeer ? .connected : peerConnection.getPeerConnection()?.iceConnectionState ?? .new

            DispatchQueue.main.async {
                cell.setAvatarFor(actor)
                cell.connectionState = connectionState
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let participantCell = cell as? CallParticipantViewCell else { return }

        let peerConnection = peersInCall[indexPath.row]
        self.updateParticipantCell(cell: participantCell, withPeerConnection: peerConnection)
    }

    // MARK: - Call Controller delegate

    func callControllerDidJoinCall(_ callController: NCCallController!) {
        self.setCallStateForPeersInCall()

        // Show chat if it was visible before room switch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if self.showChatAfterRoomSwitch, self.chatViewController == nil {
                self.showChatAfterRoomSwitch = false
                self.toggleChatView()
            }
        }
    }

    func callControllerDidFailedJoiningCall(_ callController: NCCallController!, statusCode: Int, errorReason: String!) {
        DispatchQueue.main.async {
            let isAppActive = UIApplication.shared.applicationState == .active

            if isAppActive {
                self.presentJoinError(errorReason)
            } else {
                CallKitManager.sharedInstance().endCall(self.room.token, withStatusCode: statusCode)
            }
        }
    }

    func callControllerDidEndCall(_ callController: NCCallController!) {
        self.finishCall()
    }

    func callController(_ callController: NCCallController!, peerJoined peer: NCPeerConnection!) {
        // Always add a joined peer, even if the peer doesn't publish any streams (yet)
        self.addPeer(peer)
    }

    func callController(_ callController: NCCallController!, peerLeft peer: NCPeerConnection!) {
        self.removePeer(peer)
    }

    func callController(_ callController: NCCallController!, didCreateCameraController cameraController: NCCameraController!) {
        DispatchQueue.main.async {
            cameraController.localView = self.localVideoView
        }
    }

    func callControllerDidDrawFirstLocalFrame(_ callController: NCCallController!) {
        callController.getVideoEnabledState { isEnabled in
            DispatchQueue.main.async {
                self.setLocalVideoViewWrapperHidden(!isEnabled)
            }
        }
    }

    func callController(_ callController: NCCallController!, userPermissionsChanged permissions: NCPermission) {
        self.setAudioMuteButtonEnabled(permissions.contains(.canPublishAudio) && callController.isMicrophoneAccessAvailable())
        self.setVideoDisableButtonEnabled(permissions.contains(.canPublishVideo) && callController.isCameraAccessAvailable())
    }

    func callController(_ callController: NCCallController!, didCreateLocalAudioTrack audioTrack: RTCAudioTrack?) {
        guard let audioTrack else {
            // No audio track was created, probably because there are no publishing rights or microphone access was denied
            self.setAudioMuteButtonEnabled(false)
            self.setAudioMuteButtonActive(false)

            return
        }

        self.setAudioMuteButtonActive(audioTrack.isEnabled)
    }

    func callController(_ callController: NCCallController!, didCreateLocalVideoTrack videoTrack: RTCVideoTrack?) {
        guard let videoTrack, !isAudioOnly else {
            // No video track was created, probably because there are no publishing rights or camera access was denied
            self.setVideoDisableButtonEnabled(false)
            self.setVideoDisableButtonActive(false)
            self.userDisabledVideo = true

            return
        }

        self.setVideoDisableButtonActive(videoTrack.isEnabled)

        // We set _userDisabledVideo = YES so the proximity sensor doesn't enable it.
        if !videoTrack.isEnabled {
            self.userDisabledVideo = true
        }
    }

    func callController(_ callController: NCCallController!, didAdd remoteStream: RTCMediaStream!, ofPeer remotePeer: NCPeerConnection!) {
        WebRTCCommon.shared.assertQueue()

        DispatchQueue.main.async {
            let renderView = RTCMTLVideoView(frame: .zero)

            WebRTCCommon.shared.dispatch {
                if let videoTrack = remotePeer.getRemoteStream()?.videoTracks.first {
                    renderView.delegate = self
                    videoTrack.add(renderView)
                }
            }

            if remotePeer.roomType == kRoomTypeVideo {
                self.videoRenderersDict[remotePeer.peerIdentifier] = renderView

                if self.indexPath(forPeerIdentifier: remotePeer.peerIdentifier) != nil {
                    // This peer already exists in the collection view, so we can just update its cell
                    let isVideoDisabled = self.isAudioOnly || remotePeer.isRemoteVideoDisabled

                    self.updatePeer(remotePeer) { cell in
                        cell.setVideoView(renderView)
                        cell.videoDisabled = isVideoDisabled
                    }
                } else {
                    // This is a new peer, add it
                    self.addPeer(remotePeer)
                }
            } else if remotePeer.roomType == kRoomTypeScreen {
                self.screenRenderersDict[remotePeer.peerId] = renderView
                self.screenPeersInCall.append(remotePeer)
                self.showScreenOfPeer(remotePeer)

                self.updatePeer(remotePeer) { cell in
                    cell.screenShared = true
                }

                self.sortPeersInCall()
                self.updateSnapshot()
            }
        }
    }

    func callController(_ callController: NCCallController!, didRemove remoteStream: RTCMediaStream!, ofPeer remotePeer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, iceStatusChanged state: RTCIceConnectionState, ofPeer peer: NCPeerConnection!) {
        if state == .closed {
            DispatchQueue.main.async {
                if peer.roomType == kRoomTypeVideo {
                    self.removePeer(peer)
                } else if peer.roomType == kRoomTypeScreen {
                    self.removeScreensharingOfPeer(peer)
                }
            }
        } else if peer.roomType == kRoomTypeVideo {
            self.updatePeer(peer) { cell in
                cell.connectionState = state
            }
        }
    }

    func callController(_ callController: NCCallController!, didAdd dataChannel: RTCDataChannel!) {

    }

    func callController(_ callController: NCCallController!, didReceiveDataChannelMessage message: String!, fromPeer peer: NCPeerConnection!) {
        switch message {
        case "audioOn", "audioOff":
            self.updatePeer(peer) { cell in
                cell.audioDisabled = peer.isRemoteAudioDisabled
            }
        case "videoOn", "videoOff":
            if !isAudioOnly {
                self.updatePeer(peer) { cell in
                    cell.videoDisabled = peer.isRemoteVideoDisabled
                }
            }
        case "speaking", "stoppedSpeaking":
            if peersInCall.count > 1 {
                self.updatePeer(peer) { cell in
                    cell.setSpeaking(peer.isPeerSpeaking)
                }
                // Add to speakers and sort participants if needed
                if message == "speaking" {
                    self.addSpeakerAndPromoteIfNeeded(peer)
                }
            }
        case "raiseHand":
            self.updatePeer(peer) { cell in
                cell.setRaiseHand(peer.isHandRaised)
            }
        default:
            break
        }
    }

    func callController(_ callController: NCCallController!, didReceiveNick nick: String!, fromPeer peer: NCPeerConnection!) {
        self.updatePeer(peer) { cell in
            cell.displayName = nick
        }

        if peer.peerId == self.presentedScreenPeerId {
            DispatchQueue.main.async {
                self.screenshareLabel.text = nick
            }
        }
    }

    func callController(_ callController: NCCallController!, didReceiveUnshareScreenFromPeer peer: NCPeerConnection!) {
        self.removeScreensharingOfPeer(peer)
    }

    func callController(_ callController: NCCallController!, didReceiveForceMuteActionForPeerId peerId: String!) {
        if peerId == callController.signalingSessionId() {
            self.forceMuteAudio()
        }
    }

    func callController(_ callController: NCCallController!, didReceiveReaction reaction: String!, fromPeer peer: NCPeerConnection!) {
        guard !reaction.isEmpty else { return }

        DispatchQueue.main.async {
            var user = NSLocalizedString("Guest", comment: "")

            if let peerName = peer.peerName, !peerName.isEmpty {
                user = peerName
            }

            self.addReaction(reaction, fromUser: user)
        }
    }

    func callControllerIsReconnectingCall(_ callController: NCCallController!) {
        DispatchQueue.main.async {
            // Cancel any pending operations
            self.pendingPeerInserts = []
            self.pendingPeerDeletions = []
            self.pendingPeerUpdates = []
            self.peersInCall = []

            // Reset a potential queued batch update
            self.batchUpdateTimer?.invalidate()
            self.batchUpdateTimer = nil

            // Force the collectionView to reload all data
            self.applyInitialSnapshot()

            self.setCallState(.reconnecting)
        }
    }

    func callControllerWants(toHangUpCall callController: NCCallController!) {
        DispatchQueue.main.async {
            self.hangup(forAll: false)
        }
    }

    func callControllerDidChangeRecording(_ callController: NCCallController!) {
        self.adjustTopBar()

        DispatchQueue.main.async {
            var notificationText = NSLocalizedString("Call recording stopped", comment: "")

            if self.room.callRecording == .videoStarting || self.room.callRecording == .audioStarting {
                notificationText = NSLocalizedString("Call recording is starting", comment: "")
            } else if self.room.callRecording == .videoRunning || self.room.callRecording == .audioRunning {
                notificationText = NSLocalizedString("Call recording started", comment: "")
            } else if self.room.callRecording == .failed && self.room.isUserOwnerOrModerator {
                notificationText = NSLocalizedString("Call recording failed. Please contact your administrator", comment: "")
            }

            NotificationPresenter.shared().present(text: notificationText, dismissAfterDelay: 7.0, includedStyle: .dark)
        }
    }

    func callController(_ callController: NCCallController!, isSwitchingToCall token: String!, withAudioEnabled audioEnabled: Bool, andVideoEnabled videoEnabled: Bool) {
        self.setCallState(.switchingToAnotherRoom)

        // Close chat before switching to another room
        if chatViewController != nil {
            self.showChatAfterRoomSwitch = true
            self.toggleChatView()
        }

        // Connect to new call
        NCRoomsManager.sharedInstance().updateRoom(token) { roomDict, error in
            guard error == nil, let newRoom = NCRoom(dictionary: roomDict, andAccountId: self.room.accountId)
            else {
                print("Error getting room to switch")
                return
            }

            // Prepare rooms manager to switch to another room
            NCRoomsManager.sharedInstance().prepareSwitchToAnotherRoom(fromRoom: self.room.token) { _ in
                // Notify callkit about room switch
                self.delegate?.callViewController(self, wantsToSwitchFromRoom: self.room.token, toRoom: token)

                // Store user that doesn't need to be notify in case we are switching from a one2one to an extended room
                self.previousParticipants.removeAll()
                if self.room.type == .oneToOne {
                    self.previousParticipants.append(self.room.name)
                }

                // Assign new room as current room
                self.room = newRoom

                // Start call silently in new room
                self.silentCall = true

                // Save current audio and video state
                self.audioDisabledAtStart = !audioEnabled
                self.videoDisabledAtStart = !videoEnabled

                // Forget current call controller
                self.callController = nil

                // Join new room
                NCRoomsManager.sharedInstance().joinRoom(token, forCall: true)
            }
        }
    }

    func callControllerDidChangeScreenrecording(_ callController: NCCallController!) {
        self.adjustTopBar()
    }

    // MARK: - Local video

    private func getLocalVideoSize(forResolution localVideoRes: String) -> CGSize {
        var localVideoSize: CGSize = .zero
        var aspectRatio: CGFloat = 9/16

        if localVideoRes == "Low" || localVideoRes == "Normal" {
            aspectRatio = 3/4
        }

        let width = UIScreen.main.bounds.size.width / 6
        let height = UIScreen.main.bounds.size.height / 6

        // When running on MacOS the camera will always be in portrait mode
        if width < height || NCUtils.isiOSAppOnMac() {
            localVideoSize = CGSize(width: height * aspectRatio, height: height)
        } else {
            localVideoSize = CGSize(width: width, height: width * aspectRatio)
        }

        return localVideoSize
    }

    public func setLocalVideoRect() {
        let safeAreaInsets = self.view.safeAreaInsets
        let viewSize = self.view.frame.size
        let defaultPadding: CGFloat = 16
        let extraPadding: CGFloat = 60 // Padding to not cover participant name or mute indicator when there is only one other participant in the call

        let videoResolution = NCSettingsController.sharedInstance().videoSettingsModel.currentVideoResolutionSettingFromStore()
        let localVideoResolution = NCSettingsController.sharedInstance().videoSettingsModel.readableResolution(videoResolution)
        let localVideoSize = self.getLocalVideoSize(forResolution: localVideoResolution)

        let positionX = viewSize.width - localVideoSize.width - collectionViewRightConstraint.constant - safeAreaInsets.right - defaultPadding
        let positionY = viewSize.height - localVideoSize.height - collectionViewBottomConstraint.constant - safeAreaInsets.bottom - extraPadding
        self.localVideoOriginPosition = CGPoint(x: positionX, y: positionY)

        let localVideoRect = CGRect(x: localVideoOriginPosition.x, y: localVideoOriginPosition.y, width: localVideoSize.width, height: localVideoSize.height)

        DispatchQueue.main.async {
            self.localVideoViewWrapper.frame = localVideoRect
        }
    }

    func setLocalVideoViewWrapperHidden(_ isHidden: Bool) {
        DispatchQueue.main.async {
            self.localVideoViewWrapper.isHidden = isHidden
        }
    }

    // MARK: - Connecting sound

    func startPlayingConnectingSound() {
        guard initiator, !connectingSoundAlreadyPlayed,
              let soundFilePath = Bundle.main.path(forResource: "connecting", ofType: "mp3")
        else { return }

        let soundFileURL = NSURL.fileURL(withPath: soundFilePath)

        self.soundsPlayer = try? AVAudioPlayer(contentsOf: soundFileURL)
        self.soundsPlayer?.numberOfLoops = -1
        self.soundsPlayer?.play()

        connectingSoundAlreadyPlayed = true
    }

    func stopPlayingConnectingSound() {
        self.soundsPlayer?.stop()
    }

    // MARK: - Waiting screen

    func createWaitingScreen() {
        self.avatarBackgroundImageView.backgroundColor = NCAppBranding.themeColor()

        if self.room.type == .oneToOne {
            let bgColor = ColorGenerator.shared.usernameToColor(self.room.displayName)
            self.avatarBackgroundImageView.backgroundColor = bgColor.withAlphaComponent(0.8)
        }

        self.setWaitingScreenText()
    }

    func setWaitingScreenText() {
        var waitingMessage = NSLocalizedString("Waiting for others to join call …", comment: "")

        if self.room.type == .oneToOne {
            waitingMessage = String(format: NSLocalizedString("Waiting for %@ to join call …", comment: ""), self.room.displayName)
        }

        if currentCallState == .reconnecting {
            waitingMessage = NSLocalizedString("Connecting to the call …", comment: "")
        }

        if currentCallState == .switchingToAnotherRoom {
            waitingMessage = NSLocalizedString("Switching to another conversation …", comment: "")
        }

        self.waitingLabel.text = waitingMessage
    }

    func showWaitingScreen() {
        DispatchQueue.main.async {
            self.setWaitingScreenText()
            self.collectionView.backgroundView = self.waitingView
        }
    }

    func hideWaitingScreen() {
        DispatchQueue.main.async {
            self.collectionView.backgroundView = nil
        }
    }

    // MARK: - User Interface

    public func setCallStateForPeersInCall() {
        if self.peersInCall.isEmpty {
            if self.currentCallState == .inCall {
                self.setCallState(.waitingParticipants)
            }
        } else {
            if self.currentCallState != .inCall {
                self.setCallState(.inCall)
            }
        }

        guard self.room.type != .oneToOne, let personImage = UIImage(systemName: "person.2") else { return }

        DispatchQueue.main.async {
            let participantAttachment = NSTextAttachment(image: personImage.withTintColor(self.participantsLabel.textColor))
            let participantText = NSMutableAttributedString(attachment: participantAttachment)
            participantText.append("  \(self.peersInCall.count + 1)".withFont(self.participantsLabel.font))

            self.participantsLabel.attributedText = participantText
            self.participantsLabelContainer.isHidden = false
        }
    }

    public func setCallState(_ state: CallState) {
        self.currentCallState = state

        switch state {
        case .joining, .waitingParticipants, .reconnecting:
            self.startPlayingConnectingSound()
            self.showWaitingScreen()
            self.invalidateDetailedViewTimer()
            self.showDetailedView()
            self.removeTapGestureForDetailedView()

        case .inCall:
            self.stopPlayingConnectingSound()
            self.hideWaitingScreen()

            if !self.isAudioOnly {
                self.addTapGestureForDetailedView()
                self.showDetailedViewWithTimer()
            }

        case .switchingToAnotherRoom:
            self.showWaitingScreen()
            self.invalidateDetailedViewTimer()
            self.showDetailedView()
            self.removeTapGestureForDetailedView()

        default:
            break
        }
    }

    func addTapGestureForDetailedView() {
        DispatchQueue.main.async {
            if let tapGestureForDetailedView = self.tapGestureForDetailedView {
                self.view.addGestureRecognizer(tapGestureForDetailedView)
            }
        }
    }

    func removeTapGestureForDetailedView() {
        DispatchQueue.main.async {
            if let tapGestureForDetailedView = self.tapGestureForDetailedView {
                self.view.removeGestureRecognizer(tapGestureForDetailedView)
            }
        }
    }

    func showDetailedView() {
        self.isDetailedViewVisible = true
        self.showPeersInfo()
    }

    func showDetailedViewWithTimer() {
        if isDetailedViewVisible {
            self.hideDetailedView()
        } else {
            self.showDetailedView()
            self.setDetailedViewTimer()
        }
    }

    func hideDetailedView() {
        // Keep detailed view visible while push to talk is active
        if pushToTalkActive {
            self.setDetailedViewTimer()
            return
        }

        isDetailedViewVisible = false
        self.hidePeersInfo()
        self.invalidateDetailedViewTimer()
    }

    func setAudioMuteButtonActive(_ isActive: Bool) {
        DispatchQueue.main.async {
            var micStatusString: String

            if isActive {
                micStatusString = NSLocalizedString("Microphone enabled", comment: "")
                self.audioMuteButton.setImage(.init(systemName: "mic.fill", withConfiguration: self.barButtonsConfiguration), for: .normal)
            } else {
                micStatusString = NSLocalizedString("Microphone disabled", comment: "")
                self.audioMuteButton.setImage(.init(systemName: "mic.slash.fill", withConfiguration: self.barButtonsConfiguration), for: .normal)
            }

            self.audioMuteButton.accessibilityValue = micStatusString
        }
    }

    func setAudioMuteButtonEnabled(_ isEnabled: Bool) {
        DispatchQueue.main.async {
            self.audioMuteButton.isEnabled = isEnabled
        }
    }

    func setVideoDisableButtonActive(_ isActive: Bool) {
        DispatchQueue.main.async {
            var cameraStatusString: String

            if isActive {
                cameraStatusString = NSLocalizedString("Camera enabled", comment: "")
                self.videoDisableButton.setImage(.init(systemName: "video.fill", withConfiguration: self.barButtonsConfiguration), for: .normal)
            } else {
                cameraStatusString = NSLocalizedString("Camera disabled", comment: "")
                self.videoDisableButton.setImage(.init(systemName: "video.slash.fill", withConfiguration: self.barButtonsConfiguration), for: .normal)
            }

            self.videoDisableButton.accessibilityValue = cameraStatusString
        }
    }

    func setVideoDisableButtonEnabled(_ isEnabled: Bool) {
        DispatchQueue.main.async {
            self.videoDisableButton.isEnabled = isEnabled
        }
    }

    func adjustTopBar() {
        DispatchQueue.main.async {
            // Enable/Disable video buttons
            self.videoDisableButton.isHidden = self.isAudioOnly
            self.switchCameraButton.isHidden = self.isAudioOnly
            self.videoCallButton.isHidden = !self.isAudioOnly

            self.lowerHandButton.isHidden = !self.isHandRaised

            // Only when the server supports recording-v1 we have access to callStartTime, otherwise hide the label
            self.callTimeLabel.isHidden = !NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRecordingV1)

            let audioController = NCAudioController.sharedInstance()
            self.speakerButton.isHidden = !audioController.isAudioRouteChangeable()

            self.recordingButton.isHidden = !self.room.callRecordingIsInActiveState

            // Differ between starting a call recording and an actual running call recording
            if self.room.callRecording == .videoStarting || self.room.callRecording == .audioStarting {
                self.recordingButton.tintColor = .systemGray
            } else {
                self.recordingButton.tintColor = .systemRed
            }

            // When the horizontal size is compact (e.g. iPhone portrait) we don't show the 'End call' text on the button
            // Don't make assumptions about the device here, because with split screen even an iPad can have a compact width
            if self.traitCollection.horizontalSizeClass == .compact {
                self.setHangUpButtonWithTitle(false)
            } else {
                self.setHangUpButtonWithTitle(true)
            }

            // Make sure we get the correct frame for the stack view, after changing the visibility of buttons
            self.topBarView.setNeedsLayout()
            self.topBarView.layoutIfNeeded()

            // Hide titleView if we don't have enough space
            // Don't do it in one go, as then we will have some jumping
            if self.topBarButtonStackView.frame.origin.x < 200 {
                self.setHangUpButtonWithTitle(false)
                self.titleView.isHidden = true
                self.stackViewToTitleViewConstraint.isActive = false
            } else {
                self.titleView.isHidden = false
                self.stackViewToTitleViewConstraint.isActive = true
            }

            // Need to update the layout again, if we changed it here
            self.topBarView.setNeedsLayout()
            self.topBarView.layoutIfNeeded()

            // Hide the speaker button to make some more room for higher priority buttons
            // This should only be the case for iPhone SE (1st Gen) when recording is active and/or hand is raised
            if self.topBarButtonStackView.frame.origin.x < 0 {
                self.speakerButton.isHidden = true
            }

            self.topBarView.setNeedsLayout()
            self.topBarView.layoutIfNeeded()

            if self.topBarButtonStackView.frame.origin.x < 0 {
                self.callTimeLabel.isHidden = true
            }

            if (self.room.canModerate || self.room.type == .oneToOne),
               NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityPublishingPermissions) {

                var alternativeHangUpAction: UIAction

                if self.room.type == .oneToOne {
                    alternativeHangUpAction = UIAction(title: NSLocalizedString("Leave call", comment: ""), image: .init(systemName: "phone.down.fill"), handler: { [unowned self] _ in
                        self.hangup(forAll: false)
                    })
                } else {
                    alternativeHangUpAction = UIAction(title: NSLocalizedString("End call for everyone", comment: ""), image: .init(systemName: "phone.down.fill"), handler: { [unowned self] _ in
                        self.hangup(forAll: true)
                    })
                }

                alternativeHangUpAction.attributes = .destructive

                self.hangUpButton.menu = UIMenu(children: [alternativeHangUpAction])
            }
        }
    }

    func setHangUpButtonWithTitle(_ showTitle: Bool) {
        if showTitle {
            self.hangUpButton.setTitle(NSLocalizedString("End call", comment: ""), for: .normal)
            self.hangUpButton.setTitleColor(.gray, for: .highlighted)
            self.hangUpButton.contentEdgeInsets = .init(top: 0, left: 16, bottom: 0, right: 24)
            self.hangUpButton.titleEdgeInsets = .init(top: 0, left: 8, bottom: 0, right: -8)
        } else {
            self.hangUpButton.setTitle("", for: .normal)
            self.hangUpButton.contentEdgeInsets = .zero
            self.hangUpButton.titleEdgeInsets = .zero
        }
    }

    func adjustConstraints() {
        let rightConstraintConstant = self.getRightSideConstraintConstant()
        self.collectionViewRightConstraint.constant = rightConstraintConstant

        if self.traitCollection.horizontalSizeClass == .compact {
            self.collectionViewLeftConstraint.constant = 0
        } else {
            self.collectionViewLeftConstraint.constant = 8
        }

        if self.traitCollection.verticalSizeClass == .compact {
            self.collectionViewBottomConstraint.constant = 0
            self.sideBarViewBottomConstraint.constant = 0
        } else {
            self.collectionViewBottomConstraint.constant = 8
            self.sideBarViewBottomConstraint.constant = 8
        }
    }

    func showScreensharingPicker() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let broadcastPicker = RPSystemBroadcastPickerView(frame: .init(x: 0, y: 0, width: 10, height: 10))
        broadcastPicker.preferredExtension = "\(bundleIdentifier).BroadcastUploadExtension"
        broadcastPicker.showsMicrophoneButton = false
        broadcastPicker.showPicker()
    }

    // swiftlint:disable:next cyclomatic_complexity
    func getMoreButtonMenuItems() -> [UIMenuElement] {
        guard let callController else { return [] }

        var items: [UIMenuElement] = []

        // Add speaker button to menu if it was hidden from topbar
        let audioController = NCAudioController.sharedInstance()
        if self.speakerButton.isHidden, audioController.isAudioRouteChangeable() {
            var speakerImage = UIImage(systemName: "speaker.slash.fill")
            var speakerActionTitle = NSLocalizedString("Disable speaker", comment: "speaker = Loudspeaker, device")

            if !audioController.isSpeakerActive {
                speakerImage = UIImage(systemName: "speaker.wave.3.fill")
                speakerActionTitle = NSLocalizedString("Enable speaker", comment: "")
            }

            let shouldShowAirPlayButton = audioController.numberOfAvailableInputs > 1
            if shouldShowAirPlayButton {
                speakerImage = UIImage(systemName: "airplayaudio")
                speakerActionTitle = NSLocalizedString("Audio options", comment: "")
            }

            let action = UIAction(title: speakerActionTitle, image: speakerImage) { [unowned self] _ in
                if shouldShowAirPlayButton {
                    self.airplayView.showPicker()
                } else {
                    self.speakerButtonPressed(nil)
                }
            }

            items.append(action)
        }

        // Raise hand
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRaiseHand) {
            var raiseHandTitle = NSLocalizedString("Raise hand", comment: "")

            if isHandRaised {
                raiseHandTitle = NSLocalizedString("Lower hand", comment: "")
            }

            items.append(UIAction(title: raiseHandTitle, image: .init(systemName: "hand.raised.fill"), handler: { [unowned self] _ in
                callController.raiseHand(!self.isHandRaised)
                self.isHandRaised = !self.isHandRaised
                self.adjustTopBar()
            }))
        }

        // Send a reaction
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: room.accountId)

        // Disable swiftlint -> not supported on Realm object
        // swiftlint:disable:next empty_count
        if let serverCapabilities, serverCapabilities.callReactions.count > 0, let callReactions = serverCapabilities.callReactions.value(forKey: "self") as? [String] {
            var reactionItems: [UIMenuElement] = []

            for reaction in callReactions {
                reactionItems.append(UIAction(title: String(reaction), handler: { [unowned self] _ in
                    callController.sendReaction(reaction)

                    if let account = room.account {
                        self.addReaction(reaction, fromUser: account.userDisplayName)
                    }
                }))
            }

            var currentItemsCount = 0
            var temporaryReactionItems: [UIMenuElement] = []
            var temporaryReactionMenus: [UIMenu] = []

            for reactionAction in reactionItems {
                currentItemsCount += 1
                temporaryReactionItems.append(reactionAction)

                if currentItemsCount >= 2 {
                    let inlineReactionMenu = UIMenu(title: "", options: .displayInline, children: temporaryReactionItems)
                    inlineReactionMenu.preferredElementSize = .small

                    temporaryReactionMenus.append(inlineReactionMenu)
                    temporaryReactionItems = []
                    currentItemsCount = 0
                }
            }

            if currentItemsCount > 0 {
                // Add a last item, in case there's one
                let inlineReactionMenu = UIMenu(title: "", options: .displayInline, children: temporaryReactionItems)
                inlineReactionMenu.preferredElementSize = .small

                temporaryReactionMenus.append(inlineReactionMenu)
            }

            // Replace the plain actions with the newly create inline menus
            reactionItems = temporaryReactionMenus

            let reactionMenu = UIMenu(title: NSLocalizedString("Send a reaction", comment: ""), image: .init(systemName: "face.smiling"), children: reactionItems)
            items.append(reactionMenu)
        }

        // Start/Stop recording
        if self.room.isUserOwnerOrModerator, NCSettingsController.sharedInstance().isRecordingEnabled() {
            var recordingImage = UIImage(systemName: "record.circle.fill")
            var recordingActionTitle = NSLocalizedString("Start recording", comment: "")

            if self.room.callRecordingIsInActiveState {
                recordingImage = UIImage(systemName: "stop.circle.fill")
                recordingActionTitle = NSLocalizedString("Stop recording", comment: "")
            }

            items.append(UIAction(title: recordingActionTitle, image: recordingImage, handler: { [unowned self] _ in
                if self.room.callRecordingIsInActiveState {
                    self.showStopRecordingConfirmationDialog()
                } else {
                    callController.startRecording()
                }
            }))
        }

        // Background blur
        if !self.isAudioOnly {
            var blurActionImage = UIImage(systemName: "person.and.background.dotted")
            var blurActionTitle = NSLocalizedString("Enable blur", comment: "")

            if callController.isBackgroundBlurEnabled() {
                blurActionImage = UIImage(systemName: "person.crop.rectangle")
                blurActionTitle = NSLocalizedString("Disable blur", comment: "")
            }

            items.append(UIAction(title: blurActionTitle, image: blurActionImage, handler: { [unowned self] _ in
                callController.enableBackgroundBlur(!callController.isBackgroundBlurEnabled())
                self.adjustTopBar()
            }))
        }

        // Screensharing
        var screensharingImage = UIImage(systemName: "rectangle.inset.filled.on.rectangle")
        var screensharingActionTitle = NSLocalizedString("Enable screensharing", comment: "")

        if callController.screensharingActive {
            screensharingImage = UIImage(systemName: "rectangle.on.rectangle.slash")
            screensharingActionTitle = NSLocalizedString("Stop screensharing", comment: "")
        }

        items.append(UIAction(title: screensharingActionTitle, image: screensharingImage, handler: { [unowned self] _ in
            self.showScreensharingPicker()
        }))

        var moderatorItems: [UIMenuElement] = []

        // Add participant to a one2one call
        if self.room.type == .oneToOne && self.room.canAddParticipants {
            moderatorItems.append(UIAction(title: NSLocalizedString("Add participants", comment: ""), subtitle: NSLocalizedString("Start a new group conversation", comment: ""), image: .init(systemName: "person.badge.plus"), handler: { [unowned self] _ in
                if let addParticipantsVC = AddParticipantsTableViewController(for: self.room) {
                    self.present(NCNavigationController(rootViewController: addParticipantsVC), animated: true)
                }
            }))
        }

        // Mute others
        if self.room.canModerate {
            moderatorItems.append(UIAction(title: NSLocalizedString("Mute others", comment: ""), image: .init(systemName: "mic.slash.fill"), handler: { [unowned self] _ in
                self.callController?.forceMuteOthers()
            }))
        }

        items.append(UIMenu(options: .displayInline, children: moderatorItems))

        return items
    }

    func adjustSpeakerButton() {
        DispatchQueue.main.async {
            let audioController = NCAudioController.sharedInstance()
            self.setSpeakerButtonActive(audioController.isSpeakerActive)

            // If the visibility of the speaker button does not reflect the route changeability
            // we need to try and adjust the top bar
            if self.speakerButton.isHidden == audioController.isAudioRouteChangeable() {
                self.adjustTopBar()
            }

            // Show AirPlay  button if there are more audio routes available
            if audioController.numberOfAvailableInputs > 1 {
                self.setSpeakerButtonWithAirplayButton()
            } else {
                self.airplayView.removeFromSuperview()
            }
        }
    }

    func setDetailedViewTimer() {
        self.invalidateDetailedViewTimer()
        self.detailedViewTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(self.hideDetailedView), userInfo: nil, repeats: false)
    }

    func invalidateDetailedViewTimer() {
        self.detailedViewTimer?.invalidate()
        self.detailedViewTimer = nil
    }

    func presentJoinError(_ message: String) {
        var alertTitle = String(format: NSLocalizedString("Could not join %@ call", comment: ""), self.room.displayName)

        if room.type == .oneToOne {
            alertTitle = String(format: NSLocalizedString("Could not join call with %@", comment: ""), self.room.displayName)
        }

        let alert = UIAlertController(title: alertTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            self.hangup(forAll: false)
        })

        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }

    func adjustLocalVideoPositionFromOriginPosition(_ position: CGPoint) {
        let safeAreaInsets = localVideoViewWrapper.superview?.safeAreaInsets ?? .zero

        let edgeInsetTop = 16 + topBarView.frame.origin.y + topBarView.frame.size.height
        let edgeInsetLeft = 16 + safeAreaInsets.left + collectionViewLeftConstraint.constant
        let edgeInsetBottom = 16 + safeAreaInsets.bottom + collectionViewBottomConstraint.constant
        let edgeInsetRight = 16 + safeAreaInsets.right + collectionViewRightConstraint.constant

        let edgeInsets = UIEdgeInsets(top: edgeInsetTop, left: edgeInsetLeft, bottom: edgeInsetBottom, right: edgeInsetRight)

        let parentSize = localVideoViewWrapper.superview?.bounds.size ?? .zero
        let viewSize = localVideoViewWrapper.bounds.size

        var newPosition = position

        // Adjust left
        if newPosition.x < edgeInsets.left {
            newPosition = CGPoint(x: edgeInsets.left, y: newPosition.y)
        }

        // Adjust top
        if newPosition.y < edgeInsets.top {
            newPosition = CGPoint(x: newPosition.x, y: edgeInsets.top)
        }

        // Adjust right
        if newPosition.x > parentSize.width - viewSize.width - edgeInsets.right {
            newPosition = CGPoint(x: parentSize.width - viewSize.width - edgeInsets.right, y: newPosition.y)
        }

        // Adjust bottom
        if newPosition.y > parentSize.height - viewSize.height - edgeInsets.bottom {
            newPosition = CGPoint(x: newPosition.x, y: parentSize.height - viewSize.height - edgeInsets.bottom)
        }

        let newFrame = CGRect(origin: .init(x: newPosition.x, y: newPosition.y), size: localVideoViewWrapper.frame.size)

        UIView.animate(withDuration: 0.3) {
            self.localVideoViewWrapper.frame = newFrame
        }
    }

    func localVideoDragged(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view, view == self.localVideoViewWrapper else { return }

        switch gesture.state {
        case .began:
            self.localVideoDragStartingPoint = view.center
        case .changed:
            guard let localVideoDragStartingPoint else { return }

            let translation = gesture.translation(in: view)
            self.localVideoViewWrapper.center = .init(x: localVideoDragStartingPoint.x + translation.x, y: localVideoDragStartingPoint.y + translation.y)
        case .ended:
            self.localVideoOriginPosition = view.frame.origin
            self.adjustLocalVideoPositionFromOriginPosition(localVideoOriginPosition)
        default:
            break
        }
    }

    func callDurationTimerUpdate() {
        let currentTimestamp = Int(Date().timeIntervalSince1970)

        // In case we are the ones who start the call, we don't have the server-side callStartTime, so we set it locally
        if self.room.callStartTime == 0 {
            self.room.callStartTime = currentTimestamp
        }

        // Make sure that the remote callStartTime is not in the future
        let callStartTime = min(self.room.callStartTime, currentTimestamp)

        let callDuration = currentTimestamp - callStartTime
        let oneHourInSeconds = 60 * 60

        let hours = callDuration / 3600
        let minutes = (callDuration / 60) % 60
        let seconds = callDuration % 60

        if hours > 0 {
            self.callTimeLabel.text = String(format: "%lu:%02lu:%02lu", hours, minutes, seconds)
        } else {
            self.callTimeLabel.text = String(format: "%02lu:%02lu", minutes, seconds)
        }

        if self.topBarButtonStackView.frame.origin.x < 0 {
            self.adjustTopBar()
        }

        if callDuration == oneHourInSeconds {
            let callRunningFor1h = NSLocalizedString("The call has been running for one hour", comment: "")
            NotificationPresenter.shared().present(text: callRunningFor1h, dismissAfterDelay: 7.0, includedStyle: .dark)
        }
    }

    // MARK: - Call actions

    func handlePushToTalk(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began {
            self.pushToTalkStart()
        } else {
            self.pushToTalkEnd()
        }
    }

    func pushToTalkStart() {
        guard let callController else { return }

        callController.getAudioEnabledState { isEnabled in
            guard !isEnabled else { return }

            self.setAudioMuted(false)

            DispatchQueue.main.async {
                self.buttonFeedbackGenerator.impactOccurred()
                self.pushToTalkActive = true
            }
        }
    }

    func pushToTalkEnd() {
        guard pushToTalkActive else { return }

        self.setAudioMuted(true)
        self.pushToTalkActive = false
    }

    @IBAction func audioButtonPressed(_ sender: Any) {
        guard let callController else { return }

        callController.getAudioEnabledState { isEnabled in
            if CallKitManager.isCallKitAvailable() {
                DispatchQueue.main.async {
                    CallKitManager.sharedInstance().changeAudioMuted(isEnabled, forCall: self.room.token)
                }
            } else {
                self.setAudioMuted(isEnabled)
            }
        }
    }

    func forceMuteAudio() {
        guard let callController else { return }

        callController.getAudioEnabledState { isEnabled in
            // When we are already muted, no need to mute again
            guard isEnabled else { return }

            self.setAudioMuted(true)

            let micDisabledString = NSLocalizedString("Microphone disabled", comment: "")
            let forceMutedString = NSLocalizedString("You have been muted by a moderator", comment: "")

            DispatchQueue.main.async {
                NotificationPresenter.shared().present(title: micDisabledString, subtitle: forceMutedString, includedStyle: .dark)
                NotificationPresenter.shared().dismiss(afterDelay: 7.0)
            }
        }
    }

    func setAudioMuted(_ muted: Bool) {
        guard let callController else { return }

        callController.enableAudio(!muted)
        self.setAudioMuteButtonActive(!muted)
    }

    @IBAction func videoButtonPressed(_ sender: Any) {
        guard let callController else { return }

        callController.getVideoEnabledState { isEnabled in
            self.setLocalVideoEnabled(!isEnabled)
            self.userDisabledVideo = isEnabled
        }
    }

    func disableLocalVideo() {
        self.setLocalVideoEnabled(false)
    }

    func enableLocalVideo() {
        self.setLocalVideoEnabled(true)
    }

    func setLocalVideoEnabled(_ enabled: Bool) {
        guard let callController else { return }

        callController.enableVideo(enabled)

        self.setLocalVideoViewWrapperHidden(!enabled)
        self.setVideoDisableButtonActive(enabled)
    }

    @IBAction func switchCameraButtonPressed(_ sender: Any) {
        guard let callController else { return }

        callController.switchCamera()
        self.flipLocalVideoViewWrapper()
    }

    func flipLocalVideoViewWrapper() {
        let animation = CATransition()
        animation.duration = 0.5
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        animation.type = CATransitionType(rawValue: "oglFlip")
        animation.subtype = CATransitionSubtype.fromRight

        self.localVideoViewWrapper.layer.add(animation, forKey: nil)
    }

    @IBAction func speakerButtonPressed(_ sender: Any?) {
        if NCAudioController.sharedInstance().isSpeakerActive {
            self.disableSpeaker()
            self.userDisabledSpeaker = true
        } else {
            self.enableSpeaker()
            self.userDisabledSpeaker = false
        }
    }

    func disableSpeaker() {
        self.setSpeakerButtonActive(false)

        WebRTCCommon.shared.dispatch {
            NCAudioController.sharedInstance().setAudioSessionToVoiceChatMode()
        }
    }

    func enableSpeaker() {
        self.setSpeakerButtonActive(true)

        WebRTCCommon.shared.dispatch {
            NCAudioController.sharedInstance().setAudioSessionToVideoChatMode()
        }
    }

    func setSpeakerButtonActive(_ active: Bool) {
        DispatchQueue.main.async {
            let speakerStatusString: String

            if active {
                speakerStatusString = NSLocalizedString("Speaker enabled", comment: "speaker = Loudspeaker, device")
                self.speakerButton.setImage(.init(systemName: "speaker.wave.3.fill", withConfiguration: self.barButtonsConfiguration), for: .normal)
            } else {
                speakerStatusString = NSLocalizedString("Speaker disabled", comment: "speaker = Loudspeaker, device")
                self.speakerButton.setImage(.init(systemName: "speaker.slash.fill", withConfiguration: self.barButtonsConfiguration), for: .normal)
            }

            self.speakerButton.accessibilityValue = speakerStatusString
            self.speakerButton.accessibilityHint = NSLocalizedString("Double tap to enable or disable the speaker", comment: "")
        }
    }

    func setSpeakerButtonWithAirplayButton() {
        DispatchQueue.main.async {
            self.speakerButton.setImage(nil, for: .normal)
            self.speakerButton.accessibilityValue = NSLocalizedString("AirPlay button", comment: "")
            self.speakerButton.accessibilityHint = NSLocalizedString("Double tap to select different audio routes", comment: "")
            self.speakerButton.addSubview(self.airplayView)
        }
    }

    @IBAction func hangupButtonPressed(_ sender: Any) {
        self.hangup(forAll: (room.type == .oneToOne))
    }

    func hangup(forAll forAllParticipants: Bool) {
        guard !hangingUp else { return }

        hangingUp = true

        // Dismiss possible notifications
        // swiftlint:disable:next notification_center_detachment
        NotificationCenter.default.removeObserver(self)

        // Make sure we don't try to receive messages while hanging up
        if let chatViewController {
            chatViewController.leaveChat()
            self.chatViewController = nil
        }

        // Make sure there's no menu interfering with our dismissal
        self.moreMenuButton?.contextMenuInteraction?.dismissMenu()
        self.hangUpButton?.contextMenuInteraction?.dismissMenu()

        self.delegate?.callViewControllerWantsToBeDismissed(self)

        callController?.stopCapturing()
        localVideoViewWrapper.isHidden = true

        DispatchQueue.main.async {
            for peerConnection in self.peersInCall {
                let videoRenderer = self.videoRenderersDict[peerConnection.peerIdentifier]
                self.videoRenderersDict.removeValue(forKey: peerConnection.peerIdentifier)

                guard let videoRenderer else { continue }

                WebRTCCommon.shared.dispatch {
                    peerConnection.getRemoteStream()?.videoTracks.first?.remove(videoRenderer)
                }
            }

            for peerConnection in self.screenPeersInCall {
                let screenRenderer = self.screenRenderersDict[peerConnection.peerIdentifier]
                self.screenRenderersDict.removeValue(forKey: peerConnection.peerId)

                guard let screenRenderer else { continue }

                WebRTCCommon.shared.dispatch {
                    peerConnection.getRemoteStream()?.videoTracks.first?.remove(screenRenderer)
                }
            }

            self.callDurationTimer?.invalidate()
        }

        if callController != nil {
            callController?.leaveCall(forAll: forAllParticipants)
        } else {
            self.finishCall()
        }
    }

    @IBAction func videoCallButtonPressed(_ sender: Any) {
        self.showUpgradeToVideoCallDialog()
    }

    func showUpgradeToVideoCallDialog() {
        let confirmTitle = NSLocalizedString("Do you want to enable your camera?", comment: "")
        let confirmMessage = NSLocalizedString("If you enable your camera, this call will be interrupted for a few seconds.", comment: "")

        let confirmDialog = UIAlertController(title: confirmTitle, message: confirmMessage, preferredStyle: .alert)
        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("Enable", comment: ""), style: .default) { _ in
            self.upgradeToVideoCall()
        })

        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        self.present(confirmDialog, animated: true)
    }

    func upgradeToVideoCall() {
        self.videoCallUpgrade = true
        self.hangup(forAll: false)
    }

    @IBAction func toggleChatButtonPressed(_ sender: Any) {
        self.toggleChatView()
    }

    func getRightSideConstraintConstant() -> CGFloat {
        var constant: CGFloat = 0

        if self.sideBarWidthConstraint.constant > 0 {
            // Take sidebar width into account
            constant += self.sideBarWidthConstraint.constant

            // Add padding between the element and the sidebar
            constant += 8
        }

        if self.traitCollection.horizontalSizeClass == .regular {
            // On regular size classes, we also have a padding of 8 to the safe area
            constant += 8
        }

        return constant
    }

    func setSideBarVisible(_ visible: Bool, animated: Bool, withCompletion completionBlock: (() -> Void)?) {
        self.view.layoutIfNeeded()

        if visible {
            self.sideBarView.isHidden = false
            self.sideBarWidthConstraint.constant = sidebarWidth
        } else {
            self.sideBarWidthConstraint.constant = 0
        }

        let rightConstraintConstant = self.getRightSideConstraintConstant()
        self.topBarViewRightContraint.constant = rightConstraintConstant
        self.screenshareViewRightContraint.constant = rightConstraintConstant
        self.collectionViewRightConstraint.constant = rightConstraintConstant

        self.adjustTopBar()

        var localVideoViewOrigin = self.localVideoViewWrapper.frame.origin
        // Check if localVideoView needs to be moved to the right when sidebar is being closed
        if !visible {
            let sideBarWidthGap = self.collectionView.frame.size.width - sidebarWidth

            if localVideoViewOrigin.x > sideBarWidthGap {
                localVideoViewOrigin.x = self.localVideoViewWrapper.superview?.frame.size.width ?? 0
            }
        }

        let animations = {
            self.titleView.layoutIfNeeded()
            self.view.layoutIfNeeded()
            self.adjustLocalVideoPositionFromOriginPosition(localVideoViewOrigin)
        }

        let afterAnimations = {
            if !visible {
                self.sideBarView.isHidden = true
            }

            completionBlock?()
        }

        if animated {
            UIView.animate(withDuration: 0.3) {
                animations()
            } completion: { _ in
                afterAnimations()
            }
        } else {
            animations()
            afterAnimations()
        }
    }

    func adjustChatLocation() {
        guard let chatNavigationController else { return }

        if self.traitCollection.horizontalSizeClass == .compact, chatNavigationController.view.isDescendant(of: sideBarView) {
            // Chat is displayed in the sidebar, but needs to move to full screen

            // Remove chat from the sidebar and add to call view
            chatNavigationController.view.removeFromSuperview()
            self.view.addSubview(chatNavigationController.view)

            // Show the navigationbar in case of fullscreen and adjust the frame
            chatNavigationController.setNavigationBarHidden(false, animated: false)
            chatNavigationController.view.frame = self.view.bounds

            // Finally hide the sidebar
            self.setSideBarVisible(false, animated: false, withCompletion: nil)
        } else if self.traitCollection.horizontalSizeClass == .regular, chatNavigationController.view.isDescendant(of: self.view) {
            // Chat is fullscreen, but should move to the sidebar

            // Remove chat from the call view and move it to the sidebar
            chatNavigationController.view.removeFromSuperview()
            self.sideBarView.addSubview(chatNavigationController.view)

            // Show the sidebar to have the correct bounds
            self.setSideBarVisible(true, animated: false, withCompletion: nil)

            let sideBarViewBounds = self.sideBarView.bounds
            chatNavigationController.view.frame = CGRect(x: sideBarViewBounds.origin.x, y: sideBarViewBounds.origin.y, width: sidebarWidth, height: sideBarViewBounds.size.height)

            // Don't show the navigation bar when we show the chat in the sidebar
            chatNavigationController.setNavigationBarHidden(true, animated: false)
        }
    }

    func showChat() {
        if chatNavigationController == nil {
            guard let room = NCDatabaseManager.sharedInstance().room(withToken: room.token, forAccountId: room.accountId),
                  let account = room.account,
                  let chatViewController = ChatViewController(forRoom: room, withAccount: account)
            else { return }

            chatViewController.presentedInCall = true

            self.chatViewController = chatViewController
            self.chatNavigationController = UINavigationController(rootViewController: chatViewController)
        }

        guard let chatNavigationController else { return }

        self.addChild(chatNavigationController)

        if self.traitCollection.horizontalSizeClass == .compact {
            // Show chat fullscreen
            self.view.addSubview(chatNavigationController.view)

            chatNavigationController.view.frame = self.view.bounds
            chatNavigationController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        } else {
            // Show chat in sidebar
            self.sideBarView.addSubview(chatNavigationController.view)

            let sideBarViewBounds = self.sideBarView.bounds
            chatNavigationController.view.frame = CGRect(x: sideBarViewBounds.origin.x, y: sideBarViewBounds.origin.y, width: sidebarWidth, height: sideBarViewBounds.size.height)

            // Make sure the width does not change when collapsing the side bar (weird animation)
            chatNavigationController.view.autoresizingMask = .flexibleHeight

            chatNavigationController.setNavigationBarHidden(true, animated: false)

            self.setSideBarVisible(true, animated: true) {
                chatNavigationController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
        }

        chatNavigationController.didMove(toParent: self)
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard chatNavigationController != nil else { return }

        if previousTraitCollection?.horizontalSizeClass != self.traitCollection.horizontalSizeClass {
            // Need to adjust the position of the chat, either sidebar -> fullscreen or fullscreen -> sidebar
            self.adjustChatLocation()
        }
    }

    public func toggleChatView() {
        if let chatViewController, let chatNavigationController {
            self.view.layoutIfNeeded()

            // Make sure we have a nice animation when closing the side bar and the chat is not squished
            chatNavigationController.view.autoresizingMask = .flexibleHeight

            self.setSideBarVisible(false, animated: true) { [unowned self] in
                chatViewController.leaveChat()
                self.chatViewController = nil

                chatNavigationController.willMove(toParent: nil)
                chatNavigationController.view.removeFromSuperview()
                chatNavigationController.removeFromParent()

                self.chatNavigationController = nil

                if !isAudioOnly, currentCallState == .inCall {
                    self.addTapGestureForDetailedView()
                    self.showDetailedViewWithTimer()
                }
            }
        } else {
            self.showChat()

            if !isAudioOnly {
                self.view.bringSubviewToFront(localVideoViewWrapper)
            }

            self.removeTapGestureForDetailedView()
        }
    }

    func finishCall() {
        callController = nil

        if videoCallUpgrade {
            videoCallUpgrade = false
            self.delegate?.callViewControllerWantsVideoCallUpgrade(self)
        } else {
            self.delegate?.callViewControllerDidFinish(self)
        }
    }

    @IBAction func lowerHandButtonPressed(_ sender: Any) {
        guard let callController else { return }

        callController.raiseHand(false)
        self.isHandRaised = false
        self.adjustTopBar()
    }

    @IBAction func videoRecordingButtonPressed(_ sender: Any) {
        if !room.canModerate {
            let notificationText = NSLocalizedString("This call is being recorded", comment: "")
            NotificationPresenter.shared().present(text: notificationText, dismissAfterDelay: 7.0, includedStyle: .dark)

            return
        }

        self.showStopRecordingConfirmationDialog()
    }

    func showStopRecordingConfirmationDialog() {
        let confirmTitle = NSLocalizedString("Stop recording", comment: "")
        let confirmMessage = NSLocalizedString("Do you want to stop the recording?", comment: "")

        let confirmDialog = UIAlertController(title: confirmTitle, message: confirmMessage, preferredStyle: .alert)
        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("Stop", comment: "Action to 'Stop' a recording"), style: .destructive) { _ in
            self.callController?.stopRecording()
        })

        confirmDialog.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        self.present(confirmDialog, animated: true)
    }

    // MARK: - Call Reactions

    func addReaction(_ reaction: String, fromUser user: String) {
        let callReactionView = CallReactionView(frame: .zero)
        callReactionView.setReaction(reaction: reaction, actor: user)

        // Schedule when to show reaction
        var delayBetweenReactions = reactionViewAnimationDuration / maxReactionsOnScreen
        let now = Date().timeIntervalSince1970

        if lastScheduledReaction < now {
            delayBetweenReactions = (now - lastScheduledReaction > delayBetweenReactions) ? 0 : delayBetweenReactions
            lastScheduledReaction = now
        }

        lastScheduledReaction += delayBetweenReactions

        let delay = lastScheduledReaction - now
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.showReaction(callReactionView)
        }
    }

    func showReaction(_ callReactionView: CallReactionView) {
        let callViewSize = self.view.bounds.size
        let calLReactionSize = callReactionView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)

        let minLeftPosition = callViewSize.width * 0.05
        let maxLeftPosition = callViewSize.width * 0.2

        var randomLeftPosition = minLeftPosition + CGFloat.random(in: 0 ... maxLeftPosition - minLeftPosition + 1)

        let startPosition = callViewSize.height - self.view.safeAreaInsets.bottom - calLReactionSize.height
        let minTopPosition = startPosition / 2
        let maxTopPosition = minTopPosition * 1.2
        let randomTopPosition = minTopPosition + CGFloat.random(in: 0 ... maxTopPosition - minTopPosition + 1)

        if callViewSize.width - calLReactionSize.width < 0 {
            randomLeftPosition = minLeftPosition
        }

        let reactionInitialPosition = CGRect(x: randomLeftPosition, y: startPosition, width: calLReactionSize.width, height: calLReactionSize.height)

        callReactionView.frame = reactionInitialPosition

        self.view.addSubview(callReactionView)
        self.view.bringSubviewToFront(callReactionView)

        UIView.animate(withDuration: 2.0) {
            callReactionView.frame = CGRect(x: reactionInitialPosition.origin.x, y: randomTopPosition, width: reactionInitialPosition.width, height: reactionInitialPosition.height)
        }

        UIView.animate(withDuration: 1.0, delay: 1.0) {
            callReactionView.alpha = 0
        } completion: { _ in
            callReactionView.removeFromSuperview()
        }
    }

    // MARK: - Screensharing

    func showScreenOfPeer(_ peer: NCPeerConnection) {
        DispatchQueue.main.async {
            guard let renderView = self.screenRenderersDict[peer.peerId] else { return }

            self.screensharingView.replaceContentView(renderView)
            self.screensharingView.bringSubviewToFront(self.closeScreensharingButton)

            // The screenPeer does not have a name associated to it, try to get the nonScreenPeer
            var peerDisplayName = NSLocalizedString("Guest", comment: "")

            if let nonScreenPeer = self.peerConnection(forPeerId: peer.peerId), let peerName = nonScreenPeer.peerName, !peerName.isEmpty {
                peerDisplayName = peerName
            }

            self.presentedScreenPeerId = peer.peerId
            self.screenshareLabel.text = peerDisplayName
            self.screensharingView.bringSubviewToFront(self.screenshareLabelContainer)

            UIView.transition(with: self.screensharingView, duration: 0.4, options: .transitionCrossDissolve) {
                self.screensharingView.isHidden = false
            }
        }

        // Enable/Disable detailed view with tap gesture
        // in voice only call when screensharing is enabled
        if isAudioOnly {
            self.addTapGestureForDetailedView()
            self.showDetailedViewWithTimer()
        }
    }

    func removeScreensharingOfPeer(_ peer: NCPeerConnection) {
        DispatchQueue.main.async {
            guard let screenRenderer = self.screenRenderersDict[peer.peerId],
                  let screenPeerConnection = self.screenPeerConnection(forPeerId: peer.peerId)
            else { return }

            self.presentedScreenPeerId = nil

            self.screenRenderersDict.removeValue(forKey: peer.peerId)
            self.updatePeer(peer) { cell in
                cell.screenShared = false
            }

            if self.screensharingView.contentView == screenRenderer {
                self.closeScreensharingButtonPressed(self)
            }

            WebRTCCommon.shared.dispatch {
                screenPeerConnection.getRemoteStream()?.videoTracks.first?.remove(screenRenderer)
            }

            self.screenPeersInCall.removeAll { $0 == peer }
        }
    }

    @IBAction func closeScreensharingButtonPressed(_ sender: Any) {
        DispatchQueue.main.async {
            UIView.transition(with: self.screensharingView, duration: 0.4, options: .transitionCrossDissolve) {
                self.screensharingView.isHidden = true
            }
        }

        // Back to normal voice only UI
        if isAudioOnly {
            self.invalidateDetailedViewTimer()
            self.showDetailedView()
            self.removeTapGestureForDetailedView()
        }
    }

    // MARK: - RTCVideoViewDelegate

    func videoView(_ videoView: any RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        guard let mtlVideoView = videoView as? RTCMTLVideoView else { return }

        DispatchQueue.main.async {
            for (peerIdentifier, rendererView) in self.videoRenderersDict.filter({ $0.value == mtlVideoView }) {
                rendererView.frame = CGRect(origin: .zero, size: size)

                if let indexPath = self.indexPath(forPeerIdentifier: peerIdentifier),
                   let participantCell = self.collectionView.cellForItem(at: indexPath) as? CallParticipantViewCell {

                    participantCell.setRemoteVideoSize(size)
                }
            }

            for (_, rendererView) in self.screenRenderersDict.filter({ $0.value == mtlVideoView }) {
                rendererView.frame = CGRect(origin: .zero, size: size)

                if self.screensharingView.contentView == rendererView {
                    self.screensharingSize = rendererView.frame.size
                    self.screensharingView.contentViewSize = rendererView.frame.size
                    self.screensharingView.resizeContentView()
                }
            }
        }
    }

    // MARK: - Cell updates

    @nonobjc
    private func indexPathAndPeer(with predicate: (NCPeerConnection) -> Bool) -> (indexPath: IndexPath, peer: NCPeerConnection)? {
        for peerIndex in peersInCall.indices {
            let peer = peersInCall[peerIndex]

            if predicate(peer) {
                return (IndexPath(row: peerIndex, section: 0), peer)
            }
        }

        return nil
    }

    private func peerConnection(with predicate: (NCPeerConnection) -> Bool) -> NCPeerConnection? {
        for peer in peersInCall where predicate(peer) {
            return peer
        }

        for peer in screenPeersInCall where predicate(peer) {
            return peer
        }

        return nil
    }

    internal func indexPath(forPeerIdentifier peerIdentifier: String) -> IndexPath? {
        return self.indexPathAndPeer(with: { $0.peerIdentifier == peerIdentifier })?.indexPath
    }

    internal func indexPath(forPeerId peerId: String) -> IndexPath? {
        return self.indexPathAndPeer(with: { $0.peerId == peerId })?.indexPath
    }

    internal func peerConnection(forPeerIdentifier peerIdentifier: String) -> NCPeerConnection? {
        return self.peerConnection(with: { $0.peerIdentifier == peerIdentifier })
    }

    internal func peerConnection(forPeerId peerId: String) -> NCPeerConnection? {
        return self.peerConnection(with: { $0.peerId == peerId && $0.roomType == kRoomTypeVideo })
    }

    internal func screenPeerConnection(forPeerId peerId: String) -> NCPeerConnection? {
        return self.peerConnection(with: { $0.peerId == peerId && $0.roomType == kRoomTypeScreen })
    }

    func addPeer(_ peer: NCPeerConnection) {
        DispatchQueue.main.async {
            // Store added time
            if peer.addedTime == 0 {
                peer.addedTime = Int(Date().timeIntervalSince1970 * 1000)
            }
            // Add peer to collection view
            if self.peersInCall.isEmpty {
                // Don't delay adding the first peer
                self.peersInCall.append(peer)
                self.updateSnapshot()
            } else if !self.pendingPeerInserts.contains(peer) {
                // Delay updating the collection view a bit to allow batch updating
                self.pendingPeerInserts.append(peer)
                self.scheduleBatchCollectionViewUpdate()
            }
        }
    }

    func removePeer(_ peer: NCPeerConnection) {
        DispatchQueue.main.async {
            if self.pendingPeerInserts.contains(peer) {
                // The peer is a pending insert, but was removed before the batch update
                // In this case we can just remove the pending insert
                self.pendingPeerInserts.removeAll(where: { $0 == peer })
            } else {
                self.pendingPeerDeletions.append(peer)
                self.scheduleBatchCollectionViewUpdate()
            }
        }
    }

    func updatePeer(_ peer: NCPeerConnection, block: @escaping (CallParticipantViewCell) -> Void) {
        DispatchQueue.main.async {
            if let indexPath = self.indexPath(forPeerId: peer.peerId) {
                if let cell = self.collectionView.cellForItem(at: indexPath) as? CallParticipantViewCell {
                    block(cell)
                }
            } else {
                // The participant might not be added at this point -> delay the update
                let pendingUpdate = PendingCellUpdate(peer: peer, block: block)
                self.pendingPeerUpdates.append(pendingUpdate)
            }
        }
    }

    func scheduleBatchCollectionViewUpdate() {
        dispatchPrecondition(condition: .onQueue(.main))

        if self.batchUpdateTimer == nil {
            self.batchUpdateTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(self.batchCollectionViewUpdate), userInfo: nil, repeats: false)
        }
    }

    func batchCollectionViewUpdate() {
        self.batchUpdateTimer = nil

        // Pending updates are only added when the peer was not found in the collection view (e.g wasn't added yet)
        // Therefore we only check for inserts and deletions here, as an update is probably linked to an insert anyway
        if pendingPeerInserts.isEmpty, pendingPeerDeletions.isEmpty {
            return
        }

        // Remove peer and renderers
        for peer in pendingPeerDeletions {
            // Video renderers
            let videoRenderer = self.videoRenderersDict[peer.peerIdentifier]
            self.videoRenderersDict.removeValue(forKey: peer.peerIdentifier)

            if let videoRenderer {
                WebRTCCommon.shared.dispatch {
                    peer.getRemoteStream()?.videoTracks.first?.remove(videoRenderer)
                }
            }
            // Remove peer
            self.peersInCall.removeAll { $0.peerIdentifier == peer.peerIdentifier }
        }

        // Add all new peers
        self.peersInCall.append(contentsOf: pendingPeerInserts)

        // Sort peers in call
        self.sortPeersInCall()

        // Update collection view snapshot
        self.updateSnapshot()

        // Process pending updates
        for pendingUpdate in pendingPeerUpdates {
            self.updatePeer(pendingUpdate.peer, block: pendingUpdate.block)
        }

        pendingPeerInserts = []
        pendingPeerDeletions = []
        pendingPeerUpdates = []
    }

    func showPeersInfo() {
        DispatchQueue.main.async {
            for case let cell as CallParticipantViewCell in self.collectionView.visibleCells {
                UIView.animate(withDuration: 0.3) {
                    cell.peerNameLabel.alpha = 1
                    cell.audioOffIndicator.alpha = 1
                    cell.layoutIfNeeded()
                }
            }
        }
    }

    func hidePeersInfo() {
        DispatchQueue.main.async {
            for case let cell as CallParticipantViewCell in self.collectionView.visibleCells {
                UIView.animate(withDuration: 0.3) {
                    // Don't hide raise hand indicator, that should always be visible
                    cell.peerNameLabel.alpha = 0
                    cell.audioOffIndicator.alpha = 0
                    cell.layoutIfNeeded()
                }
            }
        }
    }

    // MARK: - NCChatTitleViewDelegate

    func chatTitleViewTapped(_ chatTitleView: NCChatTitleView?) {
        let roomInfoVC = RoomInfoUIViewFactory.create(room: self.room, showDestructiveActions: false)
        roomInfoVC.modalPresentationStyle = .pageSheet

        let navController = UINavigationController(rootViewController: roomInfoVC)
        let cancelButton = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { _ in
            roomInfoVC.dismiss(animated: true)
        })

        if #unavailable(iOS 26.0) {
            cancelButton.tintColor = NCAppBranding.themeTextColor()
        }

        navController.navigationBar.topItem?.leftBarButtonItem = cancelButton

        self.present(navController, animated: true)
    }
}
