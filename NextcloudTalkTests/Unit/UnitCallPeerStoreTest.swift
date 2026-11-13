//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import WebRTC
@testable import NextcloudTalk

final class UnitCallPeerStoreTest: XCTestCase {

    private var store: CallPeerStore!
    private var changes: [[CallPeerStore.RemovedRenderer]] = []

    override func setUp() {
        super.setUp()

        changes = []
        store = CallPeerStore()
        store.onPeersChanged = { [unowned self] removedRenderers in
            self.changes.append(removedRenderers)
        }
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // NCPeerConnection may only be created on the WebRTC queue
    private func makePeer(_ sessionId: String, sid: String = "1", roomType: String = kRoomTypeVideo) -> NCPeerConnection {
        var peer: NCPeerConnection!
        let semaphore = DispatchSemaphore(value: 0)

        WebRTCCommon.shared.dispatch {
            peer = NCPeerConnection(sessionId: sessionId, sid: sid, andICEServers: [], forAudioOnlyCall: true)
            peer.roomType = roomType
            semaphore.signal()
        }

        semaphore.wait()

        return peer
    }

    private func peerIdentifiers() -> [String] {
        return store.peers.map { $0.peerIdentifier }
    }

    // MARK: - Joining and leaving

    func testFirstPeerIsAddedImmediately() {
        let peer = makePeer("a")

        store.add(peer)

        XCTAssertEqual(peerIdentifiers(), ["a-1"])
        XCTAssertEqual(changes.count, 1)
        XCTAssertNotEqual(peer.addedTime, 0)
    }

    func testFurtherPeersAreBatched() {
        store.add(makePeer("a"))
        store.add(makePeer("b"))
        store.add(makePeer("c"))

        XCTAssertEqual(peerIdentifiers(), ["a-1"])
        XCTAssertEqual(changes.count, 1)

        store.flushPendingChanges()

        XCTAssertEqual(peerIdentifiers(), ["a-1", "b-1", "c-1"])
        XCTAssertEqual(changes.count, 2)
    }

    func testBatchIsAppliedAfterDelay() {
        store.batchDelay = 0.05
        store.add(makePeer("a"))
        store.add(makePeer("b"))

        let applied = expectation(description: "Batch applied")
        store.onPeersChanged = { _ in applied.fulfill() }

        wait(for: [applied], timeout: 2)

        XCTAssertEqual(peerIdentifiers(), ["a-1", "b-1"])
    }

    func testDuplicatePeersAreIgnored() {
        store.add(makePeer("a"))
        store.add(makePeer("b"))

        // A different object for the same participant, e.g. from didAddStream after peerJoined
        store.add(makePeer("a"))
        store.add(makePeer("b"))
        store.flushPendingChanges()

        XCTAssertEqual(peerIdentifiers(), ["a-1", "b-1"])
    }

    func testPeerLeavingBeforeBeingShownCausesNoChange() {
        store.add(makePeer("a"))

        let peer = makePeer("b")
        store.add(peer)
        store.remove(peer)
        store.flushPendingChanges()

        XCTAssertEqual(peerIdentifiers(), ["a-1"])
        XCTAssertEqual(changes.count, 1)
    }

    func testLeavingPeerReturnsItsRenderer() {
        let peer = makePeer("a")
        let renderer = RTCMTLVideoView(frame: .zero)

        store.add(peer)
        store.setVideoRenderer(renderer, forPeerIdentifier: peer.peerIdentifier)
        store.remove(peer)

        XCTAssertEqual(peerIdentifiers(), ["a-1"], "Leaving is batched as well")

        store.flushPendingChanges()

        XCTAssertEqual(peerIdentifiers(), [])
        XCTAssertEqual(changes.last?.count, 1)
        XCTAssertTrue(changes.last?.first?.peer === peer)
        XCTAssertTrue(changes.last?.first?.renderer === renderer)
        XCTAssertNil(store.videoRenderer(forPeerIdentifier: peer.peerIdentifier))
    }

    func testRemoveAllPeersDropsPendingChanges() {
        store.add(makePeer("a"))
        store.add(makePeer("b"))

        store.removeAllPeers()

        XCTAssertEqual(peerIdentifiers(), [])

        store.flushPendingChanges()

        XCTAssertEqual(peerIdentifiers(), [])
        XCTAssertEqual(changes.count, 1, "Only the first peer caused a change")
    }

    // MARK: - Screen shares

    func testScreenPeersAreDeduplicatedByPeerId() {
        let first = makePeer("a", sid: "1", roomType: kRoomTypeScreen)
        let second = makePeer("a", sid: "2", roomType: kRoomTypeScreen)

        store.addScreenPeer(first)
        store.addScreenPeer(makePeer("b", roomType: kRoomTypeScreen))
        store.addScreenPeer(second)

        XCTAssertEqual(store.screenPeers.map { $0.peerIdentifier }, ["b-1", "a-2"])
        XCTAssertTrue(store.screenPeer(forPeerId: "a") === second)
    }

    func testLookupsDistinguishVideoAndScreenPeers() {
        let videoPeer = makePeer("a")
        let screenPeer = makePeer("a", sid: "2", roomType: kRoomTypeScreen)

        store.add(videoPeer)
        store.addScreenPeer(screenPeer)

        XCTAssertTrue(store.peer(forPeerId: "a") === videoPeer)
        XCTAssertTrue(store.screenPeer(forPeerId: "a") === screenPeer)
        XCTAssertTrue(store.peer(forPeerIdentifier: "a-2") === screenPeer)
    }

    // MARK: - Speakers

    func testSpeakersAreOrderedByMostRecent() {
        let a = makePeer("a")
        let b = makePeer("b")

        XCTAssertTrue(store.addSpeaker(a))
        XCTAssertTrue(store.addSpeaker(b))
        XCTAssertFalse(store.addSpeaker(b), "Already the most recent speaker")
        XCTAssertTrue(store.addSpeaker(a))

        XCTAssertEqual(store.speakers.map { $0.peerIdentifier }, ["a-1", "b-1"])
    }

    // MARK: - Renderers

    func testRemoveAllRenderersReturnsVideoAndScreenRenderers() {
        let videoPeer = makePeer("a")
        let screenPeer = makePeer("b", roomType: kRoomTypeScreen)
        let videoRenderer = RTCMTLVideoView(frame: .zero)
        let screenRenderer = RTCMTLVideoView(frame: .zero)

        store.add(videoPeer)
        store.setVideoRenderer(videoRenderer, forPeerIdentifier: videoPeer.peerIdentifier)
        store.addScreenPeer(screenPeer)
        store.setScreenRenderer(screenRenderer, forPeerId: screenPeer.peerId)

        let removed = store.removeAllRenderers()

        XCTAssertEqual(removed.count, 2)
        XCTAssertTrue(removed.contains { $0.peer === videoPeer && $0.renderer === videoRenderer })
        XCTAssertTrue(removed.contains { $0.peer === screenPeer && $0.renderer === screenRenderer })
        XCTAssertNil(store.videoRenderer(forPeerIdentifier: videoPeer.peerIdentifier))
        XCTAssertNil(store.screenRenderer(forPeerId: screenPeer.peerId))
        XCTAssertFalse(store.isScreenRenderer(screenRenderer))
    }
}
