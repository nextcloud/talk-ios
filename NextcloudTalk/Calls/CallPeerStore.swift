//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WebRTC

// The peers of a call and their renderers, only accessed on the main queue
final class CallPeerStore {

    typealias PeerId = String
    typealias PeerIdentifier = String

    // Participants shown in the collection view, in the order of the current snapshot
    private(set) var peers: [NCPeerConnection] = []

    // Screen shares in the order they were started, one per peerId
    private(set) var screenPeers: [NCPeerConnection] = []

    // Most recent speaker first
    private(set) var speakers: [NCPeerConnection] = []

    private var videoRenderers: [PeerIdentifier: RTCMTLVideoView] = [:]
    private var screenRenderers: [PeerId: RTCMTLVideoView] = [:]

    typealias RemovedRenderer = (peer: NCPeerConnection, renderer: RTCMTLVideoView)

    // Called once per applied change of peers, the caller removes the renderers from their video tracks
    var onPeersChanged: ((_ removedRenderers: [RemovedRenderer]) -> Void)?

    // Joins and leaves are collected for a moment, so many participants joining at once cause a single update
    var batchDelay: TimeInterval = 0.5

    private var pendingInserts: [NCPeerConnection] = []
    private var pendingDeletions: [NCPeerConnection] = []
    private var batchTimer: Timer?

    deinit {
        batchTimer?.invalidate()
    }

    // MARK: - Peers

    func contains(_ peer: NCPeerConnection) -> Bool {
        return self.contains(peerIdentifier: peer.peerIdentifier)
    }

    func contains(peerIdentifier: String?) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return peers.contains { $0.peerIdentifier == peerIdentifier }
    }

    func add(_ peer: NCPeerConnection) {
        dispatchPrecondition(condition: .onQueue(.main))

        // A peer can be added from both peerJoined and didAddStream, a duplicate would crash the diffable data source
        let isPendingInsert = pendingInserts.contains { $0.peerIdentifier == peer.peerIdentifier }
        guard !self.contains(peer), !isPendingInsert else { return }

        if peer.addedTime == 0 {
            peer.addedTime = Int(Date().timeIntervalSince1970 * 1000)
        }

        if peers.isEmpty {
            // Don't delay the first participant
            peers.append(peer)
            onPeersChanged?([])
        } else {
            pendingInserts.append(peer)
            self.scheduleBatch()
        }
    }

    func remove(_ peer: NCPeerConnection) {
        dispatchPrecondition(condition: .onQueue(.main))

        if pendingInserts.contains(where: { $0.peerIdentifier == peer.peerIdentifier }) {
            // Never shown, so there is nothing to update
            pendingInserts.removeAll { $0.peerIdentifier == peer.peerIdentifier }
        } else {
            pendingDeletions.append(peer)
            self.scheduleBatch()
        }
    }

    // Applies pending joins and leaves right away
    func flushPendingChanges() {
        dispatchPrecondition(condition: .onQueue(.main))

        batchTimer?.invalidate()
        batchTimer = nil

        guard !pendingInserts.isEmpty || !pendingDeletions.isEmpty else { return }

        var removedRenderers: [RemovedRenderer] = []

        for peer in pendingDeletions {
            if let renderer = videoRenderers.removeValue(forKey: peer.peerIdentifier) {
                removedRenderers.append((peer, renderer))
            }

            peers.removeAll { $0.peerIdentifier == peer.peerIdentifier }
        }

        peers.append(contentsOf: pendingInserts)

        pendingInserts = []
        pendingDeletions = []

        onPeersChanged?(removedRenderers)
    }

    // Forgets all participants and pending changes without notifying, e.g. when reconnecting
    func removeAllPeers() {
        dispatchPrecondition(condition: .onQueue(.main))

        batchTimer?.invalidate()
        batchTimer = nil
        pendingInserts = []
        pendingDeletions = []
        peers = []
    }

    private func scheduleBatch() {
        guard batchTimer == nil else { return }

        batchTimer = Timer.scheduledTimer(withTimeInterval: batchDelay, repeats: false) { [weak self] _ in
            self?.flushPendingChanges()
        }
    }

    // Not inout, so the closure can safely read from the store while sorting
    func reorder(_ body: ([NCPeerConnection]) -> [NCPeerConnection]) {
        dispatchPrecondition(condition: .onQueue(.main))

        let reordered = body(peers)
        assert(Set(reordered.map { $0.peerIdentifier }) == Set(peers.map { $0.peerIdentifier }), "Reordering must not add or remove peers")

        peers = reordered
    }

    // MARK: - Lookups

    func peer(forPeerIdentifier peerIdentifier: String) -> NCPeerConnection? {
        dispatchPrecondition(condition: .onQueue(.main))
        return peers.first { $0.peerIdentifier == peerIdentifier } ?? screenPeers.first { $0.peerIdentifier == peerIdentifier }
    }

    func peer(forPeerId peerId: String) -> NCPeerConnection? {
        dispatchPrecondition(condition: .onQueue(.main))
        return peers.first { $0.peerId == peerId && $0.roomType == kRoomTypeVideo }
    }

    func screenPeer(forPeerId peerId: String) -> NCPeerConnection? {
        dispatchPrecondition(condition: .onQueue(.main))
        return screenPeers.first { $0.peerId == peerId }
    }

    // MARK: - Screen shares

    func addScreenPeer(_ peer: NCPeerConnection) {
        dispatchPrecondition(condition: .onQueue(.main))

        // didAddStream can be called more than once for the same screen share
        screenPeers.removeAll { $0.peerId == peer.peerId }
        screenPeers.append(peer)
    }

    // By peer id, as this is also called with the video peer of the presenter
    func removeScreenPeer(forPeerId peerId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        screenPeers.removeAll { $0.peerId == peerId }
    }

    func isSharingScreen(_ peer: NCPeerConnection) -> Bool {
        return self.screenRenderer(forPeerId: peer.peerId) != nil
    }

    // MARK: - Speakers

    // Returns false when the peer already was the most recent speaker
    @discardableResult
    func addSpeaker(_ peer: NCPeerConnection) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))

        if let index = speakers.firstIndex(of: peer) {
            guard index != 0 else { return false }
            speakers.remove(at: index)
        }

        speakers.insert(peer, at: 0)

        return true
    }

    // MARK: - Renderers

    func videoRenderer(forPeerIdentifier peerIdentifier: String) -> RTCMTLVideoView? {
        dispatchPrecondition(condition: .onQueue(.main))
        return videoRenderers[peerIdentifier]
    }

    func setVideoRenderer(_ renderer: RTCMTLVideoView, forPeerIdentifier peerIdentifier: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        videoRenderers[peerIdentifier] = renderer
    }

    // The caller still needs to remove the returned renderer from its video track
    func removeVideoRenderer(forPeerIdentifier peerIdentifier: String) -> RTCMTLVideoView? {
        dispatchPrecondition(condition: .onQueue(.main))
        return videoRenderers.removeValue(forKey: peerIdentifier)
    }

    func peerIdentifiers(usingVideoRenderer renderer: RTCMTLVideoView) -> [PeerIdentifier] {
        dispatchPrecondition(condition: .onQueue(.main))
        return videoRenderers.filter { $0.value == renderer }.map { $0.key }
    }

    func screenRenderer(forPeerId peerId: String) -> RTCMTLVideoView? {
        dispatchPrecondition(condition: .onQueue(.main))
        return screenRenderers[peerId]
    }

    func setScreenRenderer(_ renderer: RTCMTLVideoView, forPeerId peerId: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        screenRenderers[peerId] = renderer
    }

    // The caller still needs to remove the returned renderer from its video track
    func removeScreenRenderer(forPeerId peerId: String) -> RTCMTLVideoView? {
        dispatchPrecondition(condition: .onQueue(.main))
        return screenRenderers.removeValue(forKey: peerId)
    }

    func isScreenRenderer(_ renderer: RTCMTLVideoView) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return screenRenderers.values.contains(renderer)
    }

    // Renderers of all shown participants and screen shares, the caller removes them from their video tracks
    func removeAllRenderers() -> [RemovedRenderer] {
        dispatchPrecondition(condition: .onQueue(.main))

        var removed: [RemovedRenderer] = []

        for peer in peers {
            if let renderer = videoRenderers.removeValue(forKey: peer.peerIdentifier) {
                removed.append((peer, renderer))
            }
        }

        for peer in screenPeers {
            if let renderer = screenRenderers.removeValue(forKey: peer.peerId) {
                removed.append((peer, renderer))
            }
        }

        return removed
    }
}
