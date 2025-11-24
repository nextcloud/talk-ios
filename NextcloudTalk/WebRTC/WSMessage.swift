//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc public class WSMessage: NSObject, URLSessionWebSocketDelegate {

    public var messageId: String? {
        didSet {
            message["id"] = messageId
        }
    }

    public var message: [AnyHashable: Any]
    public var completionBlock: SendMessageCompletionBlock?

    private let sendMessageTimeoutInterval = 15.0

    private var timeoutTimer: Timer?
    private var webSocketTask: URLSessionWebSocketTask?

    public var isHelloMessage: Bool {
        return message["type"] as? String == "hello"
    }

    public var isJoinMessage: Bool {
        return message["type"] as? String == "room"
    }

    public init(message: [AnyHashable : Any], completionBlock: SendMessageCompletionBlock? = nil) {
        self.message = message
        self.completionBlock = completionBlock
    }

    public func startMessageTimeoutTimer() {
        // NSTimer uses the runloop of the current thread. Only the main thread guarantees a runloop, so make sure we dispatch it to main!
        // This is mainly a problem for the "hello message", because it's send from a NSURL delegate and the timer sometimes fails to run
        DispatchQueue.main.async {
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: self.sendMessageTimeoutInterval, repeats: false, block: { _ in
                self.executeCompletionBlock(withStatus: .socketError)
            })
        }
    }

    public func ignoreCompletionBlock() {
        DispatchQueue.main.async {
            self.completionBlock = nil
            self.timeoutTimer?.invalidate()
        }
    }

    public func executeCompletionBlock(withStatus status: NCExternalSignalingSendMessageStatus) {
        // As the timer was create on the main thread, it needs to be invalidated on the main thread as well
        DispatchQueue.main.async {
            if let completionBlock = self.completionBlock {
                completionBlock(self.webSocketTask, status)
                self.completionBlock = nil
            }

            self.timeoutTimer?.invalidate()
        }
    }

    private func webSocketMessageString() -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: self.message)
        else {
            print("Error creating websocket message")
            return nil
        }

        return String(data: jsonData, encoding: .utf8)
    }

    public func send(withWebSocket webSocket: URLSessionWebSocketTask) {
        guard let webSocketMessageString = self.webSocketMessageString()
        else {
            print("Error creating websocket message")
            self.executeCompletionBlock(withStatus: .applicationError)
            return
        }

        self.webSocketTask = webSocket

        if self.completionBlock != nil {
            self.startMessageTimeoutTimer()
        }

        let webSocketMessage = URLSessionWebSocketTask.Message.string(webSocketMessageString)

        webSocket.send(webSocketMessage) { error in
            if error != nil, self.completionBlock != nil {
                self.executeCompletionBlock(withStatus: .socketError)
            }
        }
    }
}
