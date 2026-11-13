//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVKit
import WebRTC

protocol CallPiPCoordinatorDelegate: AnyObject {
    // The participant to show when Picture in Picture starts or the shown one left
    func initialPeer(for coordinator: CallPiPCoordinator) -> NCPeerConnection?

    // Simulcast qualities depend on whether Picture in Picture is active
    func pipCoordinatorDidChangeActiveState(_ coordinator: CallPiPCoordinator)

    // Remote video blocking depends on which participant is shown
    func pipCoordinatorDidChangeShownPeer(_ coordinator: CallPiPCoordinator)
}

// Picture in Picture of a call, only accessed on the main queue
final class CallPiPCoordinator: NSObject {

    weak var delegate: CallPiPCoordinatorDelegate?

    var room: NCRoom
    var callController: NCCallController?

    private(set) var isActive = false

    // Followed like the promoted participant in speaker view while active
    private(set) var shownPeerIdentifier: String?

    private let peerStore: CallPeerStore
    private let account: TalkAccount

    private weak var sourceView: UIView?
    private var pipController: AVPictureInPictureController?
    private var pipViewController: CallPiPViewController?
    private weak var rendererAttachedPeer: NCPeerConnection?
    private var isLocalRendererAttached = false

    init(peerStore: CallPeerStore, room: NCRoom, account: TalkAccount) {
        self.peerStore = peerStore
        self.room = room
        self.account = account

        super.init()
    }

    var shownPeer: NCPeerConnection? {
        guard isActive, let shownPeerIdentifier else { return nil }

        return peerStore.peer(forPeerIdentifier: shownPeerIdentifier)
    }

    // MARK: - Lifecycle

    func setup(sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        self.sourceView = sourceView
        self.create(withInitialContentSize: CallPiPViewController.defaultContentSize)
    }

    private func create(withInitialContentSize contentSize: CGSize) {
        guard let sourceView else { return }

        // The initial window scale is determined from the preferred content size the
        // content view controller was created with (see CallPiPViewController.init),
        // so both the view controller and the controller need to be recreated when the
        // expected video size changes before Picture in Picture is started
        self.pipController?.contentSource = nil

        let pipViewController = CallPiPViewController(initialContentSize: contentSize)
        let contentSource = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView, contentViewController: pipViewController)
        let pipController = AVPictureInPictureController(contentSource: contentSource)

        // Start Picture in Picture automatically when the app is moved to the background during a call
        pipController.canStartPictureInPictureAutomaticallyFromInline = true
        pipController.delegate = self

        self.pipViewController = pipViewController
        self.pipController = pipController
    }

    // Recreate Picture in Picture when the video size of the expected initial participant
    // does not match the current content size, so the window has the correct scale and
    // aspect on the very first start (see create). Called when a video size changes,
    // but also when peers are added: a size reported while its peer was still a
    // pending insert is skipped here, because the initial peer can't be returned yet
    func recreateIfNeeded() {
        guard !isActive, UIApplication.shared.applicationState == .active,
              let pipViewController,
              let initialPeerIdentifier = delegate?.initialPeer(for: self)?.peerIdentifier,
              let rendererView = peerStore.videoRenderer(forPeerIdentifier: initialPeerIdentifier),
              let expectedContentSize = CallPiPViewController.normalizedContentSize(for: rendererView.frame.size),
              expectedContentSize != pipViewController.preferredContentSize
        else { return }

        self.create(withInitialContentSize: expectedContentSize)
    }

    func stopIfShown() {
        if let pipController, pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        }
    }

    // Also removes Picture in Picture, until setup is called again
    func stop() {
        guard let pipController else { return }

        self.didStop()

        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        }

        pipController.contentSource = nil
        self.pipController = nil
        self.pipViewController = nil
    }

    private func didStop() {
        isActive = false
        shownPeerIdentifier = nil
        self.detachRenderer()
        self.detachLocalRenderer()
        delegate?.pipCoordinatorDidChangeActiveState(self)
    }

    // MARK: - Shown participant

    func promote(_ peer: NCPeerConnection) {
        DispatchQueue.main.async {
            guard self.isActive, self.shownPeerIdentifier != peer.peerIdentifier else { return }

            self.shownPeerIdentifier = peer.peerIdentifier
            self.updateContent()
        }
    }

    func promoteNextSpeakerIfNeeded(after peer: NCPeerConnection) {
        DispatchQueue.main.async {
            // When the participant shown in Picture in Picture stops speaking, hand the
            // promotion over to a participant that is still speaking (same as in speaker view)
            guard self.isActive, self.shownPeerIdentifier == peer.peerIdentifier,
                  let nextSpeaker = self.peerStore.peers.first(where: { $0.isPeerSpeaking && $0.peerIdentifier != peer.peerIdentifier })
            else { return }

            self.promote(nextSpeaker)
        }
    }

    func updateShownPeerIfNeeded() {
        guard isActive else { return }

        // Make sure the participant shown in Picture in Picture is still in the call
        if !peerStore.contains(peerIdentifier: shownPeerIdentifier) {
            shownPeerIdentifier = delegate?.initialPeer(for: self)?.peerIdentifier
        }

        self.updateContent()
    }

    func updateContentIfNeeded(for peer: NCPeerConnection) {
        DispatchQueue.main.async {
            guard self.isActive, self.shownPeerIdentifier == peer.peerIdentifier else { return }

            self.updateContent()
        }
    }

    func reattachRendererIfNeeded(for peer: NCPeerConnection) {
        DispatchQueue.main.async {
            guard self.isActive, self.shownPeerIdentifier == peer.peerIdentifier else { return }

            // A new remote stream was added for the shown participant,
            // so the renderer needs to be attached to the new video track
            self.detachRenderer()
            self.updateContent()
        }
    }

    private func updateContent() {
        delegate?.pipCoordinatorDidChangeShownPeer(self)

        guard isActive, let pipViewController else { return }

        guard let peer = peerStore.peers.first(where: { $0.peerIdentifier == shownPeerIdentifier }) else {
            if peerStore.peers.isEmpty {
                // No other participant in the call, show the conversation avatar and name
                self.detachRenderer()
                pipViewController.showPlaceholder(for: room)
            }

            // Otherwise the participant was not added to the collection view yet,
            // in that case the content is updated when the pending insert is processed

            return
        }

        if rendererAttachedPeer !== peer {
            self.detachRenderer()
            rendererAttachedPeer = peer

            WebRTCCommon.shared.dispatch {
                peer.getRemoteStream()?.videoTracks.first?.add(pipViewController.videoRenderView)
            }
        }

        pipViewController.setVideoDisabled(peer.isRemoteVideoDisabled || !peer.hasRemoteStream())

        let callController = self.callController
        let account = self.account

        WebRTCCommon.shared.dispatch {
            let actor = callController?.getActor(fromSessionId: peer.peerId) ?? TalkActor()

            if actor.rawDisplayName.isEmpty, let peerName = peer.peerName, !peerName.isEmpty {
                actor.rawDisplayName = peerName
            }

            DispatchQueue.main.async {
                pipViewController.setAvatar(for: actor, using: account)
            }
        }
    }

    private func detachRenderer() {
        guard let pipViewController else { return }

        if let attachedPeer = rendererAttachedPeer {
            WebRTCCommon.shared.dispatch {
                attachedPeer.getRemoteStream()?.videoTracks.first?.remove(pipViewController.videoRenderView)
            }
        }

        rendererAttachedPeer = nil
        pipViewController.videoRenderView.flush()
    }

    // MARK: - Local video

    // The local video track might have been recreated while in Picture in Picture
    // (e.g. when reconnecting a call), so the renderer needs to be attached to the new track
    func reattachLocalRendererIfNeeded() {
        guard isLocalRendererAttached else { return }

        self.detachLocalRenderer()
        self.attachLocalRendererIfNeeded()
    }

    func setLocalVideoHidden(_ hidden: Bool) {
        guard isLocalRendererAttached else { return }

        pipViewController?.setLocalVideoHidden(hidden)
    }

    private func attachLocalRendererIfNeeded() {
        guard isActive, let callController, let pipViewController,
              callController.isCameraUsableWhileInBackground()
        else { return }

        isLocalRendererAttached = true

        pipViewController.localVideoRenderView.isMirrored = callController.isUsingFrontCamera()
        callController.attachRenderer(toLocalVideoTrack: pipViewController.localVideoRenderView)

        callController.getVideoEnabledState { isEnabled in
            DispatchQueue.main.async {
                guard self.isLocalRendererAttached else { return }

                pipViewController.setLocalVideoHidden(!isEnabled)
            }
        }
    }

    private func detachLocalRenderer() {
        guard let pipViewController else { return }

        if isLocalRendererAttached {
            callController?.detachRenderer(fromLocalVideoTrack: pipViewController.localVideoRenderView)
        }

        isLocalRendererAttached = false
        pipViewController.setLocalVideoHidden(true)
        pipViewController.localVideoRenderView.flush()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension CallPiPCoordinator: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        shownPeerIdentifier = delegate?.initialPeer(for: self)?.peerIdentifier
        self.updateContent()
        self.attachLocalRendererIfNeeded()
        delegate?.pipCoordinatorDidChangeActiveState(self)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // When quickly switching back to the app while Picture in Picture is still
        // animating in, the stop in appDidBecomeActive is missed, because the
        // controller was not marked as active there yet. Stop it here instead
        if UIApplication.shared.applicationState == .active {
            pictureInPictureController.stopPictureInPicture()
            return
        }

        // A size change that happened while the window was animating in was ignored
        // by AVKit, so assert the current size again now that the window is shown
        pipViewController?.reassertContentSize()
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        self.didStop()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("Failed to start Picture in Picture: \(error)")

        self.didStop()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // The call view is still presented fullscreen, nothing to restore
        completionHandler(true)
    }
}
