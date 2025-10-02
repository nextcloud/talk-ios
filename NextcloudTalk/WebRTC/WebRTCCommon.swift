//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers final class WebRTCCommon: NSObject {

    public static let shared = WebRTCCommon()

    public lazy var peerConnectionFactory: RTCPeerConnectionFactory = {
        return RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }()

    private lazy var encoderFactory: RTCVideoEncoderFactory = {
        return RTCDefaultVideoEncoderFactory()
    }()

    private lazy var decoderFactory: RTCVideoDecoderFactory = {
        return RTCDefaultVideoDecoderFactory()
    }()

    private let webrtcClientDispatchQueue = DispatchQueue(label: "webrtcClientDispatchQueue")

    private override init() {
        super.init()
    }

    // Every call into the WebRTC library must be dispatched to this queue
    public func dispatch(_ work: @escaping @convention(block) () -> Void) {
        webrtcClientDispatchQueue.async(execute: work)
    }

    public func assertQueue() {
        dispatchPrecondition(condition: .onQueue(webrtcClientDispatchQueue))
    }

    public func printNumberOfOpenSocketDescriptors() {
        print("File descriptors: \(self.openFilePaths().filter { $0 == "?" }.count)")
    }

    private func openFilePaths() -> [String] {
        // from https://developer.apple.com/forums/thread/655225?answerId=623114022#623114022
        (0..<getdtablesize()).map { fd in
            // Return "" for invalid file descriptors.
            var flags: CInt = 0
            guard fcntl(fd, F_GETFL, &flags) >= 0 else {
                return ""
            }
            // Return "?" for file descriptors not associated with a path, for
            // example, a socket.
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(fd, F_GETPATH, &path) >= 0 else {
                return "?"
            }

            return String(cString: path)
        }
    }
}
