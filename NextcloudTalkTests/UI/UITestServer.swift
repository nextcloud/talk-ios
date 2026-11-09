//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import XCTest

struct TestUser {
    let username: String
    let password: String

    static let admin = TestUser(username: TestConstants.username, password: TestConstants.password)
    static let alice = TestUser(username: "alice", password: "alice")
}

struct TestRoom {
    let token: String
    let name: String
    let owner: TestUser
}

enum UITestServerError: Error {
    case requestFailed(String)
}

// Local test servers often use a self-signed certificate, the test runner does not share the app's accepted certificates
private final class TestServerTrustDelegate: NSObject, URLSessionDelegate {

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == URL(string: TestConstants.server)?.host,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

// Prepares the server state for UI tests through the OCS API, the app is not involved
enum UITestServer {

    enum RoomType: Int {
        case group = 2
    }

    enum ListableScope: Int {
        case registeredUsers = 1
    }

    static let defaultPermissionsReactOnly = 260 // JoinCall (4) + React (256)

    private static let spreedApi = "/apps/spreed/api/v4"
    private static let chatApi = "/apps/spreed/api/v1"

    // Cookies would keep a session of the previous user alive and win over the basic auth of the next one
    private static let session = URLSession(configuration: .ephemeral, delegate: TestServerTrustDelegate(), delegateQueue: nil)

    static func createRoom(named name: String, type: RoomType = .group, as owner: TestUser = .admin) throws -> TestRoom {
        let data = try ocsRequest("POST", "\(spreedApi)/room", as: owner, body: ["roomType": type.rawValue, "roomName": name])

        guard let token = (data as? [String: Any])?["token"] as? String else {
            throw UITestServerError.requestFailed("Creating room \(name) returned no token")
        }

        return TestRoom(token: token, name: name, owner: owner)
    }

    static func deleteRoom(_ room: TestRoom) throws {
        try ocsRequest("DELETE", "\(spreedApi)/room/\(room.token)", as: room.owner)
    }

    static func enableLobby(in room: TestRoom) throws {
        try ocsRequest("PUT", "\(spreedApi)/room/\(room.token)/webinar/lobby", as: room.owner, body: ["state": 1])
    }

    static func setListable(_ scope: ListableScope, for room: TestRoom) throws {
        try ocsRequest("PUT", "\(spreedApi)/room/\(room.token)/listable", as: room.owner, body: ["scope": scope.rawValue])
    }

    static func setDefaultPermissions(_ permissions: Int, for room: TestRoom) throws {
        try ocsRequest("PUT", "\(spreedApi)/room/\(room.token)/permissions/default", as: room.owner, body: ["permissions": permissions])
    }

    static func addParticipant(_ user: TestUser, to room: TestRoom) throws {
        try ocsRequest("POST", "\(spreedApi)/room/\(room.token)/participants", as: room.owner, body: ["newParticipant": user.username, "source": "users"])
    }

    static func sendMessage(_ message: String, to room: TestRoom, as user: TestUser) throws {
        try ocsRequest("POST", "\(chatApi)/chat/\(room.token)", as: user, body: ["message": message])
    }

    // Display names of all conversations the user is a participant of
    static func roomNames(for user: TestUser) throws -> [String] {
        let data = try ocsRequest("GET", "\(spreedApi)/room", as: user)

        return (data as? [[String: Any]])?.compactMap { $0["displayName"] as? String } ?? []
    }

    static func hasTalkFeature(_ feature: String) throws -> Bool {
        let data = try ocsRequest("GET", "/cloud/capabilities", as: .admin)
        let capabilities = (data as? [String: Any])?["capabilities"] as? [String: Any]
        let features = (capabilities?["spreed"] as? [String: Any])?["features"] as? [String]

        return features?.contains(feature) ?? false
    }

    @discardableResult
    private static func ocsRequest(_ method: String, _ path: String, as user: TestUser, body: [String: Any]? = nil) throws -> Any? {
        guard let url = URL(string: "\(TestConstants.server)/ocs/v2.php\(path)") else {
            throw UITestServerError.requestFailed("Invalid path \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let credentials = Data("\(user.username):\(user.password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        var responseData: Data?
        var response: URLResponse?
        var responseError: Error?

        let semaphore = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, urlResponse, error in
            responseData = data
            response = urlResponse
            responseError = error
            semaphore.signal()
        }.resume()

        guard semaphore.wait(timeout: .now() + TestConstants.timeoutLong) == .success else {
            throw UITestServerError.requestFailed("\(method) \(path) timed out")
        }

        if let responseError {
            throw UITestServerError.requestFailed("\(method) \(path) failed: \(responseError.localizedDescription)")
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw UITestServerError.requestFailed("\(method) \(path) as \(user.username) returned \(statusCode)")
        }

        guard let responseData, !responseData.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else { return nil }

        return (json["ocs"] as? [String: Any])?["data"]
    }
}

extension XCTestCase {

    // Unique names, so leftovers of earlier runs (failed cleanups, other matrix jobs) are never picked up
    func uniqueName(_ prefix: String) -> String {
        return "\(prefix) \(UUID().uuidString.prefix(8))"
    }

    // For server state changed by requests of the app, which the test can't wait for directly
    func waitForServer(timeout: Double = TestConstants.timeoutShort, until condition: () throws -> Bool) rethrows -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if try condition() {
                return true
            }

            usleep(500_000)
        } while Date() < deadline

        return false
    }

    // Opens the chat directly through the deep link, without depending on the conversation list
    func openConversation(_ room: TestRoom, in app: XCUIApplication) {
        var components = URLComponents()
        components.scheme = "nextcloudtalk"
        components.host = "open-conversation"
        components.queryItems = [
            URLQueryItem(name: "server", value: TestConstants.server),
            URLQueryItem(name: "user", value: TestConstants.username),
            URLQueryItem(name: "withRoomToken", value: room.token)
        ]

        guard let url = components.url else {
            XCTFail("Could not build the URL to open \(room.name)")
            return
        }

        guard #available(iOS 16.4, *) else {
            XCTFail("Opening a conversation by URL requires iOS 16.4")
            return
        }

        // XCUIApplication.open would launch the app again, the system delivers the URL to the running instance
        XCUIDevice.shared.system.open(url)

        let chatNavBar = app.navigationBars["NextcloudTalk.ChatView"]
        XCTAssert(chatNavBar.waitForExistence(timeout: TestConstants.timeoutLong))
        XCTAssert(chatNavBar.textViews[room.name].waitForExistence(timeout: TestConstants.timeoutShort))
    }
}
