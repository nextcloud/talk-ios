//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
import Foundation
@testable import NextcloudTalk

class NCCallControllerDelegateMock: NSObject, NCCallControllerDelegate {

    public var expectationDidJoin = XCTestExpectation(description: "DidJoin")
    public var expectationDidEndCall = XCTestExpectation(description: "DidEndCall")

    func callControllerDidJoinCall(_ callController: NCCallController!) {
        expectationDidJoin.fulfill()
    }

    func callControllerDidFailedJoiningCall(_ callController: NCCallController!, statusCode: Int, errorReason: String!) {

    }

    func callControllerDidEndCall(_ callController: NCCallController!) {
        expectationDidEndCall.fulfill()
    }

    func callController(_ callController: NCCallController!, peerJoined peer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, peerLeft peer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, didCreateLocalAudioTrack audioTrack: RTCAudioTrack?) {

    }

    func callController(_ callController: NCCallController!, didCreateLocalVideoTrack videoTrack: RTCVideoTrack?) {

    }

    func callController(_ callController: NCCallController!, didCreateCameraController cameraController: NextcloudTalk.NCCameraController!) {

    }

    func callController(_ callController: NCCallController!, userPermissionsChanged permissions: NCPermission) {

    }

    func callController(_ callController: NCCallController!, didAdd remoteStream: RTCMediaStream!, ofPeer remotePeer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, didRemove remoteStream: RTCMediaStream!, ofPeer remotePeer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, iceStatusChanged state: RTCIceConnectionState, ofPeer peer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, didAdd dataChannel: RTCDataChannel!) {

    }

    func callController(_ callController: NCCallController!, didReceiveDataChannelMessage message: String!, fromPeer peer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, didReceiveNick nick: String!, fromPeer peer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, didReceiveUnshareScreenFromPeer peer: NCPeerConnection!) {

    }

    func callController(_ callController: NCCallController!, didReceiveForceMuteActionForPeerId peerId: String!) {

    }

    func callController(_ callController: NCCallController!, didReceiveReaction reaction: String!, fromPeer peer: NCPeerConnection!) {

    }

    func callControllerIsReconnectingCall(_ callController: NCCallController!) {

    }

    func callControllerWants(toHangUpCall callController: NCCallController!) {

    }

    func callControllerDidChangeRecording(_ callController: NCCallController!) {

    }

    func callControllerDidDrawFirstLocalFrame(_ callController: NCCallController!) {

    }

    func callControllerDidChangeScreenrecording(_ callController: NCCallController!) {

    }

    func callController(_ callController: NCCallController!, isSwitchingToCall token: String!, withAudioEnabled audioEnabled: Bool, andVideoEnabled videoEnabled: Bool) {

    }

}
