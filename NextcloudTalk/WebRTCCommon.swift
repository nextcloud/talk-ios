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
