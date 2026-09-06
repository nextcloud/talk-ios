//
//  SocketConnection.swift
//  Broadcast Extension
//
//  Created by Alex-Dan Bumbu on 22/03/2021.
//  Copyright © 2021 Atlassian Inc. All rights reserved.
//
// From https://github.com/jitsi/jitsi-meet-sdk-samples (Apache 2.0 license)
// SPDX-FileCopyrightText: 2021 Alex-Dan Bumbu, Atlassian Inc. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

import Foundation

class SocketConnection: NSObject {
    var didOpen: (() -> Void)?
    var didClose: ((Error?) -> Void)?
    var streamHasSpaceAvailable: (() -> Void)?

    private let filePath: String
    private var socketHandle: Int32 = -1
    private var address: sockaddr_un?

    // CFStream is not thread safe and close() arrives from ReplayKit or from a stream event while
    // the uploader queue is in the middle of a write, so all stream access is serialized here
    private let streamQueue = DispatchQueue(label: "talk.broadcast.socketConnection")

    private var inputStream: InputStream?
    private var outputStream: OutputStream?

    private var streamThread: Thread?
    private var streamRunLoop: RunLoop?
    private var isClosed = false

    init?(filePath path: String) {
        filePath = path
        socketHandle = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)

        guard socketHandle != -1 else {
            print("failure: create socket")
            return nil
        }
    }

    func open() -> Bool {
        print("open socket connection")

        guard FileManager.default.fileExists(atPath: filePath) else {
            print("failure: socket file missing")
            return false
        }

        guard setupAddress() == true else {
            return false
        }

        guard connectSocket() == true else {
            return false
        }

        return streamQueue.sync { () -> Bool in
            guard !isClosed else {
                return false
            }

            setupStreams()

            inputStream?.open()
            outputStream?.open()

            return true
        }
    }

    func close() {
        streamQueue.sync { () -> Void in
            self.closeStreams()
        }
    }

    func writeToStream(buffer: UnsafePointer<UInt8>, maxLength length: Int) -> Int {
        streamQueue.sync {
            outputStream?.write(buffer, maxLength: length) ?? 0
        }
    }
}

extension SocketConnection: StreamDelegate {

    // stream events are delivered on the run loop thread set up in scheduleStreams()
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            print("client stream open completed")
            if isOutputStream(aStream) {
                didOpen?()
            }
        case .hasBytesAvailable:
            guard isInputStream(aStream) else {
                break
            }

            var buffer: UInt8 = 0
            let numberOfBytesRead = streamQueue.sync {
                self.inputStream?.read(&buffer, maxLength: 1)
            }

            if numberOfBytesRead == 0 && aStream.streamStatus == .atEnd {
                print("server socket closed")

                if streamQueue.sync(execute: { self.closeStreams() }) {
                    notifyDidClose(error: nil)
                }
            }
        case .hasSpaceAvailable:
            if isOutputStream(aStream) {
                streamHasSpaceAvailable?()
            }
        case .errorOccurred:
            print("client stream error occured: \(String(describing: aStream.streamError))")
            let streamError = aStream.streamError

            if streamQueue.sync(execute: { self.closeStreams() }) {
                notifyDidClose(error: streamError)
            }
        default:
            break
        }
    }
}

private extension SocketConnection {

    func isInputStream(_ aStream: Stream) -> Bool {
        streamQueue.sync { aStream === self.inputStream }
    }

    func isOutputStream(_ aStream: Stream) -> Bool {
        streamQueue.sync { aStream === self.outputStream }
    }

    func setupAddress() -> Bool {
        var addr = sockaddr_un()
        guard filePath.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            print("failure: fd path is too long")
            return false
        }

        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            filePath.withCString {
                strncpy(ptr, $0, filePath.count)
            }
        }

        address = addr
        return true
    }

    func connectSocket() -> Bool {
        guard var addr = address else {
            return false
        }

        let status = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketHandle, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard status == noErr else {
            print("failure: \(status)")
            return false
        }

        return true
    }

    // must be called on streamQueue
    func setupStreams() {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocket(kCFAllocatorDefault, socketHandle, &readStream, &writeStream)

        inputStream = readStream?.takeRetainedValue()
        inputStream?.delegate = self
        inputStream?.setProperty(kCFBooleanTrue, forKey: Stream.PropertyKey(kCFStreamPropertyShouldCloseNativeSocket as String))

        outputStream = writeStream?.takeRetainedValue()
        outputStream?.delegate = self
        outputStream?.setProperty(kCFBooleanTrue, forKey: Stream.PropertyKey(kCFStreamPropertyShouldCloseNativeSocket as String))

        if let inputStream = inputStream, let outputStream = outputStream {
            scheduleStreams(inputStream, outputStream)
        }
    }

    // the streams get a thread of their own instead of a global queue, so closeStreams() knows
    // which run loop they ended up on and can take them off it again
    // must be called on streamQueue
    func scheduleStreams(_ input: InputStream, _ output: OutputStream) {
        let thread = Thread { [weak self] in
            guard let self = self else {
                return
            }

            let runLoop = RunLoop.current
            let scheduled = self.streamQueue.sync { () -> Bool in
                guard !self.isClosed else {
                    return false
                }

                self.streamRunLoop = runLoop
                input.schedule(in: runLoop, forMode: .common)
                output.schedule(in: runLoop, forMode: .common)

                return true
            }

            guard scheduled else {
                return
            }

            while !Thread.current.isCancelled, runLoop.run(mode: .default, before: .distantFuture) {
                // run() returns once the streams are unscheduled, which ends the thread
            }
        }

        thread.name = "talk.broadcast.socketConnection"
        streamThread = thread
        thread.start()
    }

    // returns whether this call was the one that closed the connection, so that a close coming in
    // twice, on a stream error and on the server hanging up, only reports back once
    // must be called on streamQueue
    @discardableResult
    func closeStreams() -> Bool {
        guard !isClosed else {
            return false
        }

        isClosed = true

        streamThread?.cancel()

        if let streamRunLoop = streamRunLoop {
            inputStream?.remove(from: streamRunLoop, forMode: .common)
            outputStream?.remove(from: streamRunLoop, forMode: .common)
            CFRunLoopStop(streamRunLoop.getCFRunLoop())
        }

        inputStream?.delegate = nil
        outputStream?.delegate = nil

        inputStream?.close()
        outputStream?.close()

        inputStream = nil
        outputStream = nil

        streamThread = nil
        streamRunLoop = nil

        return true
    }

    func notifyDidClose(error: Error?) {
        if didClose != nil {
            didClose?(error)
        }
    }
}
