//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import NextcloudKit
import SDWebImage
import SDWebImageSVGKitPlugin

@objcMembers
class NCAPIController: NSObject, NKCommonDelegate {

    static let shared = NCAPIController()

    // TODO: Workaround for now to not rewrite every call
    @available(*, renamed: "shared")
    static func sharedInstance() -> NCAPIController {
        return NCAPIController.shared
    }

    // MARK: - Public var
    public let kReceivedChatMessagesLimit = 100

    // MARK: - Private var
    private let kDavEndpoint = "/remote.php/dav"
    private let kNCOCSAPIVersion = "/ocs/v2.php"
    private let kNCSpreedAPIVersionBase = "/apps/spreed/api/v"

    private var authTokenCache: [String: String] = [:]
    private var requestModifierCache: [String: SDWebImageDownloaderRequestModifier] = [:]

    private lazy var defaultAPISessionManager: NCAPISessionManager = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        return NCAPISessionManager(configuration: configuration)
    }()

    private var apiSessionManagers = [String: NCAPISessionManager]()
    private var longPollingApiSessionManagers = [String: NCAPISessionManager]()
    private var calDAVSessionManagers = [String: NCCalDAVSessionManager]()

    enum ApiControllerError: Error {
        case preconditionError
        case unexpectedOcsResponse
    }

    // MARK: - Init

    override init() {
        super.init()

        self.initImageDownloaders()
    }

    internal func getAPISessionManager(forAccountId accountId: String) -> NCAPISessionManager? {
        if let cachedSessionManager = self.apiSessionManagers[accountId] {
            return cachedSessionManager
        }

        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let authHeader = self.authHeader(forAccount: account)
        else { return nil }

        let configuration = URLSessionConfiguration.default
        let cookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: accountId)
        configuration.httpCookieStorage = cookieStorage
        let apiSessionManager = NCAPISessionManager(configuration: configuration)
        apiSessionManager.requestSerializer.setValue(authHeader, forHTTPHeaderField: "Authorization")

        // As we can run max. 30s in the background, the default timeout should be lower than 30 to avoid being killed by the OS
        apiSessionManager.requestSerializer.timeoutInterval = TimeInterval(25)
        apiSessionManagers[accountId] = apiSessionManager

        return apiSessionManager
    }

    internal func getLongPollingAPISessionManager(forAccountId accountId: String) -> NCAPISessionManager? {
        if let cachedSessionManager = self.longPollingApiSessionManagers[accountId] {
            return cachedSessionManager
        }

        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let authHeader = self.authHeader(forAccount: account)
        else { return nil }

        let longConfiguration = URLSessionConfiguration.default
        let longCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: accountId)
        longConfiguration.httpCookieStorage = longCookieStorage
        let longApiSessionManager = NCAPISessionManager(configuration: longConfiguration)
        longApiSessionManager.requestSerializer.setValue(authHeader, forHTTPHeaderField: "Authorization")
        longPollingApiSessionManagers[accountId] = longApiSessionManager

        return longApiSessionManager
    }

    internal func getCalDAVSessionManager(forAccountId accountId: String) -> NCCalDAVSessionManager? {
        if let cachedSessionManager = self.calDAVSessionManagers[accountId] {
            return cachedSessionManager
        }

        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let authHeader = self.authHeader(forAccount: account)
        else { return nil }

        let calDAVConfiguration = URLSessionConfiguration.default
        let calDAVCookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: accountId)
        calDAVConfiguration.httpCookieStorage = calDAVCookieStorage
        let calDAVSessionManager = NCCalDAVSessionManager(configuration: calDAVConfiguration)
        calDAVSessionManager.requestSerializer.setValue(authHeader, forHTTPHeaderField: "Authorization")
        calDAVSessionManagers[accountId] = calDAVSessionManager

        return calDAVSessionManager
    }

    public func removeAPISessionManager(forAccount account: TalkAccount) {
        self.authTokenCache.removeValue(forKey: account.accountId)
        self.requestModifierCache.removeValue(forKey: account.accountId)
        self.apiSessionManagers.removeValue(forKey: account.accountId)
        self.longPollingApiSessionManagers.removeValue(forKey: account.accountId)
        self.calDAVSessionManagers.removeValue(forKey: account.accountId)
    }

    private func authHeader(forAccount account: TalkAccount) -> String? {
        if let cachedHeader = self.authTokenCache[account.accountId] {
            return cachedHeader
        }

        guard let token = NCKeyChainController.sharedInstance().token(forAccountId: account.accountId)
        else { return nil }

        let userTokenString = "\(account.user):\(token)"
        let data = userTokenString.data(using: .utf8)!
        let base64Encoded = data.base64EncodedString()

        let authHeader = "Basic \(base64Encoded)"
        self.authTokenCache[account.accountId] = authHeader

        return authHeader
    }

    public func setupNCCommunication(forAccount account: TalkAccount) {
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId),
              let token = NCKeyChainController.sharedInstance().token(forAccountId: account.accountId)
        else { return }

        NextcloudKit.shared.setup(account: account.accountId, user: account.user, userId: account.userId, password: token, urlBase: account.server, userAgent: NCAppBranding.userAgent(), nextcloudVersion: serverCapabilities.versionMajor, delegate: self)
    }

    private func initImageDownloaders() {
        // The defaults for the shared url cache are very low, use some sane values for caching. Apple only caches assets <= 5% of the available space.
        // Otherwise some (user) avatars will never be cached and always requested
        let sharedURLCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        URLCache.shared = sharedURLCache

        // By default SDWebImageDownloader defaults to 6 concurrent downloads (see SDWebImageDownloaderConfig)

        // Make sure we support download SVGs with SDImageDownloader
        SDImageCodersManager.shared.addCoder(SDImageSVGKCoder.shared)

        // Make sure we support self-signed certificates we trusted before
        SDWebImageDownloader.shared.config.operationClass = NCWebImageDownloaderOperation.self

        // Limit the cache size to 100 MB and prevent uploading to iCloud
        // Don't set the path to an app group in order to prevent crashes
        SDImageCache.shared.config.shouldDisableiCloud = true
        SDImageCache.shared.config.maxDiskSize = 100 * 1024 * 1024
        SDImageCache.shared.config.maxDiskAge = 60 * 60 * 24 * 7 * 4 // 4 weeks

        // We expire the cache once on app launch, see AppDelegate
        SDImageCache.shared.config.shouldRemoveExpiredDataWhenTerminate = false
        SDImageCache.shared.config.shouldRemoveExpiredDataWhenEnterBackground = false
        SDWebImageDownloader.shared.setValue(NCAppBranding.userAgent(), forHTTPHeaderField: "User-Agent")
    }

    private func getRequestModifier(forAccount account: TalkAccount) -> SDWebImageDownloaderRequestModifier? {
        if let cachedModifier = self.requestModifierCache[account.accountId] {
            return cachedModifier
        }

        guard let authHeader = self.authHeader(forAccount: account)
        else { return nil }

        let headers = [
            "Authorization": authHeader
        ]

        let requestModifier = SDWebImageDownloaderRequestModifier(headers: headers)
        self.requestModifierCache[account.accountId] = requestModifier

        return requestModifier
    }

    // MARK: - Utils

    public func authenticationBackendUrl(forAccount account: TalkAccount) -> String {
        return self.getRequestURL(forEndpoint: "signaling/backend", withAPIType: .signaling, forAccount: account)
    }

    internal func filesPath(forAccount account: TalkAccount) -> String {
        return "\(kDavEndpoint)/files/\(account.userId)"
    }

    internal func getRequestURL(forConversationEndpoint endpoint: String, forAccount account: TalkAccount) -> String {
        return self.getRequestURL(forEndpoint: endpoint, withAPIType: .conversation, forAccount: account)
    }

    @nonobjc
    internal func getRequestURL(forEndpoint endpoint: String, withAPIType apiType: NCAPIType, forAccount account: TalkAccount) -> String {
        let apiVersion = NCAPIVersion(forType: apiType, withAccount: account).rawValue
        return "\(account.server)\(kNCOCSAPIVersion)\(kNCSpreedAPIVersionBase)\(apiVersion)/\(endpoint)"
    }

    // MARK: - Rooms Controller

    private func checkProxyHeaders(for task: URLSessionDataTask, forRoom token: String, forAccount account: TalkAccount) {
        guard let response = task.response as? HTTPURLResponse,
              let proxyHash = response.value(forHTTPHeaderField: "X-Nextcloud-Talk-Proxy-Hash"),
              !proxyHash.isEmpty
        else { return }

        let query = NSPredicate(format: "token = %@ AND accountId = %@", token, account.accountId)

        // Ensure the room is known to us locally, otherwise don't try to fetch room capabilities
        guard let managedRoom = NCRoom.objects(with: query).firstObject() else { return }

        let federatedCapabilities = NCDatabaseManager.sharedInstance().federatedCapabilities(forAccountId: managedRoom.accountId, remoteServer: managedRoom.remoteServer, roomToken: managedRoom.token)

        if proxyHash == managedRoom.lastReceivedProxyHash, federatedCapabilities != nil {
            // The proxy hash is equal to our last known proxy hash and we are also able to retrieve capabilities locally -> skip fetching capabilities
            return
        }

        self.getRoomCapabilities(for: account.accountId, token: token) { roomCapabilities, proxyHash in
            if let roomCapabilities, let proxyHash {
                NCDatabaseManager.sharedInstance().setFederatedCapabilities(roomCapabilities, forAccountId: account.accountId, remoteServer: managedRoom.remoteServer, roomToken: token, withProxyHash: proxyHash)
            }
        }
    }

    @nonobjc
    @discardableResult
    public func joinRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ sessionId: String?, _ room: NCRoom?, _ error: Error?, _ statusCode: Int, _ statusReason: String?) -> Void) -> URLSessionTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants/active", forAccount: account)

        return apiSessionManager.postOcs(urlString, account: account) { ocsResponse, ocsError in
            if let ocsError {
                completionBlock(nil, nil, ocsError.error, ocsError.responseStatusCode, ocsError.errorKey)
                return
            }

            if let task = ocsResponse?.task {
                self.checkProxyHeaders(for: task, forRoom: token, forAccount: account)
            }

            var room: NCRoom?

            // Room object is returned only since Talk 11
            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityListableRooms) {
                room = NCRoom(dictionary: ocsResponse?.dataDict, andAccountId: account.accountId)

                // In case there's no token, or a non-matching token, don't return
                if room?.token != token {
                    room = nil
                }
            }

            completionBlock(ocsResponse?.dataDict?["sessionId"] as? String, room, nil, 0, nil)
        }
    }

    @nonobjc
    @discardableResult
    public func exitRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) -> URLSessionTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants/active", forAccount: account)

        return apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            if let ocsError {
                completionBlock(ocsError.error)
                return
            }

            completionBlock(nil)
        }
    }

    public func getRooms(forAccount account: TalkAccount, updateStatus: Bool, modifiedSince: Int, completionBlock: @escaping (_ rooms: [[String: AnyObject]]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        var urlString = self.getRequestURL(forConversationEndpoint: "room", forAccount: account)
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)

        let parameters: [String: Any] = [
            "noStatusUpdate": !updateStatus,
            "modifiedSince": modifiedSince
        ]

        // Since we are using "modifiedSince" only in background fetches
        // we will request including user status only when getting the complete room list
        if serverCapabilities?.userStatus == true, modifiedSince == 0 {
            urlString = urlString.appending("?includeStatus=true")
        }

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let response = ocsResponse?.task?.response as? HTTPURLResponse {
                var numberOfPendingInvitations = 0

                // If the header is not present, there are no pending invites
                if let federationInvitesString = response.value(forHTTPHeaderField: "x-nextcloud-talk-federation-invites") {
                    numberOfPendingInvitations = Int(federationInvitesString) ?? 0
                }

                if account.pendingFederationInvitations != numberOfPendingInvitations {
                    NCDatabaseManager.sharedInstance().setPendingFederationInvitationForAccountId(account.accountId, with: numberOfPendingInvitations)
                }
            }

            // TODO: Move away from generic dictionary return type
            // let rooms = ocs?.dataArrayDict.compactMap { NCRoom(dictionary: $0, andAccountId: account.accountId) }
            completionBlock(ocsResponse?.dataArrayDict, ocsError?.error)
        }
    }

    public func getRoom(forAccount account: TalkAccount, withToken token: String, completionBlock: @escaping (_ room: [String: AnyObject]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)", forAccount: account)

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError?.error)
        }
    }

    @MainActor
    @discardableResult
    public func getRoom(forAccount account: TalkAccount, withToken token: String) async throws -> NCRoom? {
        return try await withCheckedThrowingContinuation { continuation in
            self.getRoom(forAccount: account, withToken: token) { room, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: NCRoom(dictionary: room, andAccountId: account.accountId))
                }
            }
        }
    }

    @nonobjc
    public func getNoteToSelfRoom(forAccount account: TalkAccount, completionBlock: @escaping (_ room: [String: AnyObject]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/note-to-self", forAccount: account)

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError?.error)
        }
    }

    public func getListableRooms(forAccount account: TalkAccount, withSerachTerm searchTerm: String?, completionBlock: @escaping (_ rooms: [NCRoom]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "listed-room", forAccount: account)
        var parameters: [String: Any] = [:]

        if let searchTerm, !searchTerm.isEmpty {
            parameters["searchTerm"] = searchTerm
        }

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            let rooms = ocsResponse?.dataArrayDict?.compactMap { NCRoom(dictionary: $0, andAccountId: account.accountId) }
            completionBlock(rooms, ocsError?.error)
        }
    }

    public func createRoom(forAccount account: TalkAccount, withParameters parameters: [String: Any], completionBlock: @escaping (_ room: NCRoom?, _ error: OcsError?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room", forAccount: account)

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            let room = NCRoom(dictionary: ocsResponse?.dataDict, andAccountId: account.accountId)
            completionBlock(room, ocsError)
        }
    }

    public func createRoom(forAccount account: TalkAccount, withInvite invite: String?, ofType roomType: NCRoomType, andName roomName: String?, completionBlock: @escaping (_ room: NCRoom?, _ error: OcsError?) -> Void) {
        var parameters: [String: Any] = ["roomType": roomType.rawValue]

        if let invite, !invite.isEmpty {
            parameters["invite"] = invite
        }

        if let roomName, !roomName.isEmpty {
            parameters["roomName"] = roomName
        }

        self.createRoom(forAccount: account, withParameters: parameters, completionBlock: completionBlock)
    }

    @nonobjc
    public func renameRoom(_ token: String, forAccount account: TalkAccount, withName roomName: String, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)", forAccount: account)
        let parameters: [String: String] = ["roomName": roomName]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @nonobjc
    public func setRoomDescription(_ description: String?, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/description", forAccount: account)
        let parameters: [String: String] = ["description": description ?? ""]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @nonobjc
    public func setMentionPermissions(_ permissions: NCRoomMentionPermissions, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/mention-permissions", forAccount: account)
        let parameters: [String: Int] = ["mentionPermissions": permissions.rawValue]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @nonobjc
    public func makeRoomPublic(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/public", forAccount: account)

        apiSessionManager.postOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @nonobjc
    public func makeRoomPrivate(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/public", forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @nonobjc
    public func deleteRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)", forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @nonobjc
    public func unbindRoomFromObject(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/object", forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @nonobjc
    public func setPassword(_ password: String, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?, _ errorDescription: String?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/password", forAccount: account)
        let parameters: [String: String] = ["password": password]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            // When password does not match the password-policy, we receive a 400
            if ocsError?.responseStatusCode == 400 {
                // message is already translated server-side
                completionBlock(ocsError?.error, ocsError?.errorMessage)
            } else {
                completionBlock(ocsError?.error, nil)
            }
        }
    }

    public func addRoomToFavorites(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/favorite", forAccount: account)

        apiSessionManager.postOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func removeRoomFromFavorites(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/favorite", forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @MainActor
    public func setImportantState(enabled: Bool, forRoom token: String, forAccount account: TalkAccount) async throws -> NCRoom? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/important", forAccount: account)
        var ocsResponse: OcsResponse

        if enabled {
            ocsResponse = try await apiSessionManager.postOcs(urlString, account: account)
        } else {
            ocsResponse = try await apiSessionManager.deleteOcs(urlString, account: account)
        }

        return NCRoom(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
    }

    @MainActor
    public func setSensitiveState(enabled: Bool, forRoom token: String, forAccount account: TalkAccount) async throws -> NCRoom? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/sensitive", forAccount: account)
        var ocsResponse: OcsResponse

        if enabled {
            ocsResponse = try await apiSessionManager.postOcs(urlString, account: account)
        } else {
            ocsResponse = try await apiSessionManager.deleteOcs(urlString, account: account)
        }

        return NCRoom(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
    }

    @MainActor
    public func setNotificationLevel(level: NCRoomNotificationLevel, forRoom token: String, forAccount account: TalkAccount) async -> Bool {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return false }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/notify", forAccount: account)
        let parameters: [String: Int] = ["level": level.rawValue]

        let ocsResponse = try? await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)

        // Older endpoints don't return the room object
        // return NCRoom(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
        return (ocsResponse != nil)
    }

    @MainActor
    public func setCallNotificationLevel(enabled: Bool, forRoom token: String, forAccount account: TalkAccount) async -> Bool {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return false }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/notify-calls", forAccount: account)
        let parameters: [String: Bool] = ["level": enabled]

        let ocsResponse = try? await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)

        // Older endpoints don't return the room object
        // return NCRoom(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
        return (ocsResponse != nil)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func setReadOnlyState(state: NCRoomReadOnlyState, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/read-only", forAccount: account)
        let parameters: [String: Int] = ["state": state.rawValue]

        return try await apiSessionManager.putOcs(urlString, account: account, parameters: parameters)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func setLobbyState(state: NCRoomLobbyState, withTimer timer: Int, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let endpoint = NCAPIVersion(forType: .conversation, withAccount: account) >= NCAPIVersion.APIv4 ? "room/\(encodedToken)/webinar/lobby" : "room/\(encodedToken)/webinary/lobby"
        let urlString = self.getRequestURL(forConversationEndpoint: endpoint, forAccount: account)
        var parameters: [String: Int] = ["state": state.rawValue]

        if timer > 0 {
            parameters["timer"] = timer
        }

        return try await apiSessionManager.putOcs(urlString, account: account, parameters: parameters)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func setSIPState(state: NCRoomSIPState, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/webinar/sip", forAccount: account)
        let parameters: [String: Int] = ["state": state.rawValue]

        return try await apiSessionManager.putOcs(urlString, account: account, parameters: parameters)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func setListableScope(scope: NCRoomListableScope, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/listable", forAccount: account)
        let parameters: [String: Int] = ["scope": scope.rawValue]

        return try await apiSessionManager.putOcs(urlString, account: account, parameters: parameters)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func setMessageExpiration(messageExpiration: NCMessageExpiration, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/message-expiration", forAccount: account)
        let parameters: [String: Int] = ["seconds": messageExpiration.rawValue]

        return try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)
    }

    // MARK: - Participants

    @nonobjc
    @MainActor
    @discardableResult
    public func getParticipants(forRoom token: String, forAccount account: TalkAccount) async throws -> [NCRoomParticipant] {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        var urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants", forAccount: account)
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)

        if serverCapabilities?.userStatus == true {
            urlString += "?includeStatus=true"
        }

        let response = try await apiSessionManager.getOcs(urlString, account: account)
        guard let dataArrayDict = response.dataArrayDict else { throw ApiControllerError.unexpectedOcsResponse }

        let participants = dataArrayDict.compactMap { NCRoomParticipant(dictionary: $0) }

        return participants.sortedParticipants()
    }

    @MainActor
    @discardableResult
    public func addParticipant(_ participant: String, ofType type: String?, toRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants", forAccount: account)
        var parameters: [String: String] = ["newParticipant": participant]

        if let type {
            parameters["source"] = type
        }

        return try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func removeAttendee(_ attendeeId: Int, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/attendees", forAccount: account)
        let parameters: [String: Int] = ["attendeeId": attendeeId]

        return try await apiSessionManager.deleteOcs(urlString, account: account, parameters: parameters)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func removeParticipant(_ participant: String, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants", forAccount: account)
        let parameters: [String: String] = ["participant": participant]

        return try await apiSessionManager.deleteOcs(urlString, account: account, parameters: parameters)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func removeGuest(_ guest: String, forRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/guests", forAccount: account)
        let parameters: [String: String] = ["participant": guest]

        return try await apiSessionManager.deleteOcs(urlString, account: account, parameters: parameters)
    }

    @MainActor
    @discardableResult
    public func removeSelf(fromRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants/self", forAccount: account)

        return try await apiSessionManager.deleteOcs(urlString, account: account)
    }

    public enum ModeratorPermissionChangeType {
        case promoteToModerator, demoteToParticipant
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func changeModerationPermission(forParticipantId participantId: String, withType type: ModeratorPermissionChangeType, inRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/moderators", forAccount: account)
        var parameters = ["participant": participantId]

        if NCAPIVersion(forType: .conversation, withAccount: account) >= .APIv3 {
            parameters = ["attendeeId": participantId]
        }

        if type == .promoteToModerator {
            return try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)
        } else {
            return try await apiSessionManager.deleteOcs(urlString, account: account, parameters: parameters)
        }
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func resendInvitation(toParticipant participant: String?, inRoom token: String, forAccount account: TalkAccount) async throws -> OcsResponse {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/participants/resend-invitations", forAccount: account)
        var parameters: [String: String] = [:]

        if let participant {
            parameters = ["attendeeId": participant]
        }

        return try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)
    }

    // MARK: - Federation

    public func acceptFederationInvitation(for accountId: String, with invitationId: Int, completionBlock: @escaping (_ success: Bool) -> Void) {
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)!
        let urlString = self.getRequestURL(forEndpoint: "federation/invitation/\(invitationId)", withAPIType: .federation, forAccount: account)

        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(false)
            return
        }

        apiSessionManager.postOcs(urlString, account: account) { _, error in
            completionBlock(error == nil)
        }
    }

    public func rejectFederationInvitation(for accountId: String, with invitationId: Int, completionBlock: @escaping (_ success: Bool) -> Void) {
        let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)!
        let urlString = self.getRequestURL(forEndpoint: "federation/invitation/\(invitationId)", withAPIType: .federation, forAccount: account)

        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(false)
            return
        }

        apiSessionManager.deleteOcs(urlString, account: account) { _, error in
            completionBlock(error == nil)
        }
    }

    public func getFederationInvitations(for accountId: String, completionBlock: @escaping (_ invitations: [FederationInvitation]?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: accountId),
              let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId)
        else {
            completionBlock(nil)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "federation/invitation", withAPIType: .federation, forAccount: account)

        apiSessionManager.getOcs(urlString, account: account) { ocs, _ in
            let invitations = ocs?.dataArrayDict?.map { FederationInvitation(dictionary: $0, for: accountId) }
            completionBlock(invitations)
        }
    }

    // MARK: - Room capabilities

    public func getRoomCapabilities(for accountId: String, token: String, completionBlock: @escaping (_ roomCapabilities: [String: AnyObject]?, _ proxyHash: String?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil, nil)
            return
        }

        let urlString = self.getRequestURL(forConversationEndpoint: "room/\(encodedToken)/capabilities", forAccount: account)

        apiSessionManager.getOcs(urlString, account: account) { ocs, _ in
            completionBlock(ocs?.dataDict, ocs?.value(forHTTPHeaderField: "x-nextcloud-talk-proxy-hash"))
        }
    }

    // MARK: - Signaling

    @discardableResult
    public func getSignalingSettings(for account: TalkAccount, forRoom roomToken: String?, completionBlock: @escaping (_ signalingSettings: SignalingSettings?, _ error: (any Error)?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(nil, nil)
            return nil
        }

        let urlString = self.getRequestURL(forEndpoint: "signaling/settings", withAPIType: .signaling, forAccount: account)

        var parameters: [String: Any]?

        if let roomToken, let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            parameters = [
                "token": encodedToken
            ]
        }

        return apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            completionBlock(SignalingSettings(dictionary: ocsResponse?.dataDict), ocsError?.error)
        }
    }

    @MainActor
    public func sendSignalingMessages(_ messages: String, toRoom token: String, forAccount account: TalkAccount) async throws {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "signaling/\(encodedToken)", withAPIType: .signaling, forAccount: account)

        try await apiSessionManager.postOcs(urlString, account: account, parameters: ["messages": messages])
    }

    // Use non-async method here to allow cancellation from objc (as we can return a URLSessionDataTask)
    @discardableResult
    public func pullSignalingMessages(fromRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ messages: [[String: AnyObject]]?, _ error: Error?) -> Void) -> URLSessionTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "signaling/\(encodedToken)", withAPIType: .signaling, forAccount: account)

        return apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataArrayDict, ocsError?.error)
        }
    }

    // MARK: - Mentions

    @nonobjc
    public func getMentionSuggestions(for accountId: String, in roomToken: String, with searchString: String, completionBlock: @escaping (_ mentions: [MentionSuggestion]?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        else {
            completionBlock(nil)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/mentions", withAPIType: .chat, forAccount: account)

        let parameters: [String: Any] = [
            "limit": 20,
            "search": searchString,
            "includeStatus": serverCapabilities.userStatus
        ]

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocs, _ in
            let mentions = ocs?.dataArrayDict?.map { MentionSuggestion(dictionary: $0) }
            completionBlock(mentions)
        }
    }

    // MARK: - Ban

    @nonobjc
    // swiftlint:disable:next function_parameter_count
    public func banActor(for accountId: String, in roomToken: String, with actorType: String, with actorId: String, with internalNote: String?, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(false)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "ban/\(encodedToken)", withAPIType: .ban, forAccount: account)

        var parameters: [String: Any] = [
            "actorType": actorType,
            "actorId": actorId
        ]

        if let internalNote, !internalNote.isEmpty {
            parameters["internalNote"] = internalNote
        }

        apiSessionManager.post(urlString, parameters: parameters, progress: nil) { _, _ in
            completionBlock(true)
        } failure: { _, _ in
            completionBlock(false)
        }
    }

    @nonobjc
    public func listBans(for accountId: String, in roomToken: String, completionBlock: @escaping (_ bannedActors: [BannedActor]?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(nil)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "ban/\(encodedToken)", withAPIType: .ban, forAccount: account)

        apiSessionManager.getOcs(urlString, account: account) { ocs, _ in
            let actorBans = ocs?.dataArrayDict?.map { BannedActor(dictionary: $0) }
            completionBlock(actorBans)
        }
    }

    @nonobjc
    public func unbanActor(for accountId: String, in roomToken: String, with banId: Int, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(false)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "ban/\(encodedToken)/\(banId)", withAPIType: .ban, forAccount: account)

        apiSessionManager.delete(urlString, parameters: nil) { _, _ in
            completionBlock(true)
        } failure: { _, _ in
            completionBlock(false)
        }
    }

    // MARK: - AI

    public enum SummarizeChatStatus: Int {
        case success = 0
        case noMessagesFound
        case noAiProvider
        case failed
    }

    @nonobjc
    public func summarizeChat(forAccountId accountId: String, inRoom roomToken: String, fromMessageId messageId: Int, completionBlock: @escaping (_ status: SummarizeChatStatus, _ taskId: Int?, _ nextOffset: Int?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(.failed, nil, nil)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/summarize", withAPIType: .chat, forAccount: account)

        let parameters: [String: Int] = [
            "fromMessageId": messageId
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if ocsResponse?.responseStatusCode == 204 {
                completionBlock(.noMessagesFound, nil, nil)
                return
            }

            if ocsError?.responseStatusCode == 500, let error = ocsError?.dataDict?["error"] as? String, error == "ai-no-provider" {
                completionBlock(.noAiProvider, nil, nil)
                return
            }

            guard let dict = ocsResponse?.dataDict as? [String: Int] else {
                completionBlock(.failed, nil, nil)
                return
            }

            completionBlock(.success, dict["taskId"], dict["nextOffset"])
        }
    }

    public enum AiTaskStatus: Int {
        case unknown = 0
        case scheduled = 1
        case running = 2
        case successful = 3
        case failed = 4
        case cancelled = 5

        init(stringResponse: String) {
            switch stringResponse {
            case "STATUS_SCHEDULED": self = .scheduled
            case "STATUS_RUNNING": self = .running
            case "STATUS_SUCCESSFUL": self = .successful
            case "STATUS_FAILED": self = .failed
            case "STATUS_CANCELLED": self = .cancelled
            default: self = .unknown
            }
        }
    }

    @nonobjc
    public func getAiTaskById(for accountId: String, withTaskId taskId: Int, completionBlock: @escaping (_ status: AiTaskStatus, _ output: String?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(.failed, nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/taskprocessing/task/\(taskId)"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            guard ocsError == nil,
                  let taskDict = ocsResponse?.dataDict?["task"] as? [String: Any],
                  let status = taskDict["status"] as? String
            else {
                completionBlock(.failed, nil)
                return
            }

            let outputDict = taskDict["output"] as? [String: Any]
            completionBlock(AiTaskStatus(stringResponse: status), outputDict?["output"] as? String)
        }
    }

    // MARK: - Out-of-office

    @nonobjc
    public func getCurrentUserAbsence(forAccountId accountId: String, forUserId userId: String, completionBlock: @escaping (_ absenceData: CurrentUserAbsence?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)/now"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, _ in
            guard let dataDict = ocsResponse?.dataDict else {
                completionBlock(nil)
                return
            }
            completionBlock(CurrentUserAbsence(dictionary: dataDict))
        }
    }

    @nonobjc
    public func getUserAbsence(forAccountId accountId: String, forUserId userId: String, completionBlock: @escaping (_ absenceData: UserAbsence?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, _ in
            guard let dataDict = ocsResponse?.dataDict else {
                completionBlock(nil)
                return
            }
            completionBlock(UserAbsence(dictionary: dataDict))
        }
    }

    @nonobjc
    public func clearUserAbsence(forAccountId accountId: String, forUserId userId: String, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(false)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)"

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError == nil)
        }
    }

    public enum SetUserAbsenceResponse: Int {
        case unknownError = 0
        case success = 1
        case statusLengthError = 2
        case firstDayError = 3

        init(errorKey: String?) {
            switch errorKey {
            case nil: self = .success
            case "statusLength": self = .statusLengthError
            case "firstDay": self = .firstDayError
            default: self = .unknownError
            }
        }
    }

    @nonobjc
    public func setUserAbsence(forAccountId accountId: String, forUserId userId: String, withAbsence absenceData: UserAbsence, completionBlock: @escaping (_ response: SetUserAbsenceResponse) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(.unknownError)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/outOfOffice/\(encodedUserId)"
        let absenceDictionary = absenceData.asDictionary()

        apiSessionManager.postOcs(urlString, account: account, parameters: absenceDictionary) { _, ocsError in
            completionBlock(SetUserAbsenceResponse(errorKey: ocsError?.errorKey))
        }
    }

    // MARK: - Notifications

    // Needs to be of type Int to be usable from objc
    @objc public enum CallNotificationState: Int {
        case unknown, stillCurrent, roomNotFound, missedCall, participantJoined
    }

    @discardableResult
    public func getCallNotificationState(for account: TalkAccount, forRoom roomToken: String, completionBlock: @escaping (_ callNotificationState: CallNotificationState) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(.unknown)
            return nil
        }

        let urlString = self.getRequestURL(forEndpoint: "call/\(encodedToken)/notification-state", withAPIType: .call, forAccount: account)

        return apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            if ocsResponse?.responseStatusCode == 200 {
                completionBlock(.stillCurrent)
            } else if ocsResponse?.responseStatusCode == 201 {
                completionBlock(.missedCall)
            } else if ocsError?.responseStatusCode == 403 {
                completionBlock(.roomNotFound)
            } else if ocsError?.responseStatusCode == 404 {
                completionBlock(.participantJoined)
            } else {
                completionBlock(.unknown)
            }
        }
    }

    // MARK: - Archived conversations

    public func archiveRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(false)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)/archive", withAPIType: .conversation, forAccount: account)

        apiSessionManager.postOcs(urlString, account: account) { _, error in
            completionBlock(error == nil)
        }
    }

    public func unarchiveRoom(_ token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ success: Bool) -> Void) {
        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(false)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "room/\(encodedToken)/archive", withAPIType: .conversation, forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, error in
            completionBlock(error == nil)
        }
    }

    // MARK: - Push notification test

    @nonobjc
    public func testPushnotifications(forAccount account: TalkAccount) async throws -> (message: String, notificationId: Int?) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { throw ApiControllerError.preconditionError }

        let urlString = "\(account.server)/ocs/v2.php/apps/notifications/api/v3/test/self"

        let ocsResponse = try await apiSessionManager.postOcs(urlString, account: account)

        guard let dataDict = ocsResponse.dataDict,
              let message = dataDict["message"] as? String
        else { throw ApiControllerError.unexpectedOcsResponse }

        // notificationId is only returend on Nextcloud >= 32
        return (message, dataDict["nid"] as? Int)
    }

    // MARK: - Upcoming events

    @nonobjc
    func upcomingEvents(_ room: NCRoom, forAccount account: TalkAccount, completionBlock: @escaping (_ events: [CalendarEvent]) -> Void) {
        guard let encodedRoomLink = room.linkURL?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock([])
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/dav/api/v1/events/upcoming?location=\(encodedRoomLink)"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, error in
            if error == nil, let events = ocsResponse?.dataDict?["events"] as? [[String: Any]] {
                let calendarEvents = events.map { CalendarEvent(dictionary: $0) }
                completionBlock(calendarEvents)
            } else {
                completionBlock([])
            }
        }
    }

    // MARK: - Groups & Teams

    func getUserGroups(forAccount account: TalkAccount, completionBlock: @escaping (_ groupIds: [String]?, _ error: Error?) -> Void) {
        guard let encodedUserId = account.userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(nil, NSError(domain: "", code: 0, userInfo: nil))
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/cloud/users/\(encodedUserId)/groups"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            if ocsError?.error == nil, let groupdIds = ocsResponse?.dataDict?["groups"] as? [String] {
                completionBlock(groupdIds, nil)
            } else {
                completionBlock(nil, ocsError?.error)
            }
        }
    }

    func getUserTeams(forAccount account: TalkAccount, completionBlock: @escaping (_ teamIds: [String]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(nil, NSError(domain: "", code: 0, userInfo: nil))
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/circles/probecircles"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            if ocsError?.error == nil, let teamsDicts = ocsResponse?.dataArrayDict {
                let teamIds = teamsDicts.compactMap { $0["id"] as? String }
                completionBlock(teamIds, nil)
            } else {
                completionBlock(nil, ocsError?.error)
            }
        }
    }

    // MARK: - File operations

    func getFileById(forAccount account: TalkAccount, withFileId fileId: String, completionBlock: @escaping (_ file: NKFile?, _ error: NKError?) -> Void) {
        self.setupNCCommunication(forAccount: account)

        let body = """
            <?xml version=\"1.0\" encoding=\"UTF-8\"?>\
            <d:searchrequest xmlns:d=\"DAV:\" xmlns:oc=\"http://nextcloud.com/ns\">\
            <d:basicsearch>\
            <d:select>\
                <d:prop>\
                    <d:displayname />\
                    <d:getcontenttype />\
                    <d:resourcetype />\
                    <d:getcontentlength />\
                    <d:getlastmodified />\
                    <d:creationdate />\
                    <d:getetag />\
                    <d:quota-used-bytes />\
                    <d:quota-available-bytes />\
                    <oc:fileid xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:permissions xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:id xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:size xmlns:oc=\"http://owncloud.org/ns\" />\
                    <oc:favorite xmlns:oc=\"http://owncloud.org/ns\" />\
                </d:prop>\
            </d:select>\
            <d:from>\
                <d:scope>\
                    <d:href>/files/%@</d:href>\
                    <d:depth>infinity</d:depth>\
                </d:scope>\
            </d:from>\
            <d:where>\
                <d:eq>\
                    <d:prop>\
                        <oc:fileid xmlns:oc=\"http://owncloud.org/ns\" />\
                    </d:prop>\
                    <d:literal>%@</d:literal>\
                </d:eq>\
            </d:where>\
            <d:orderby />\
            </d:basicsearch>\
            </d:searchrequest>
            """

        let bodyRequest = String(format: body, account.userId, fileId)
        let options = NKRequestOptions(timeout: 60, queue: .main)

        NextcloudKit.shared.searchBodyRequest(serverUrl: account.server, requestBody: bodyRequest, showHiddenFiles: true, options: options) { _, files, _, error in
            completionBlock(files.first, error)
        }
    }

    // MARK: - Profile

    @nonobjc
    func getUserProfile(forUserId userId: String, forAccount account: TalkAccount, completionBlock: @escaping (_ info: ProfileInfo?) -> Void) {
        guard let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/profile/\(encodedUserId)"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, _ in
            // Note: HTTP 405 -> Server does not support the endpoint
            guard let dataDict = ocsResponse?.dataDict else {
                completionBlock(nil)
                return
            }

            completionBlock(ProfileInfo(dictionary: dataDict))
        }
    }

    // MARK: - Threads

    @nonobjc
    public func getThreads(for accountId: String, in roomToken: String, withLimit limit: Int = 50, completionBlock: @escaping (_ threads: [NCThread]?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/threads/recent", withAPIType: .chat, forAccount: account)

        let parameters: [String: Any] = [
            "limit": limit
        ]

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocs, _ in
            if let threads = ocs?.dataArrayDict?.map({ NCThread(dictionary: $0, andAccountId: accountId) }), !threads.isEmpty {
                NCThread.storeOrUpdateThreads(threads)
                completionBlock(threads)
            } else {
                completionBlock(nil)
            }
        }
    }

    public func getSubscribedThreads(for accountId: String, withLimit limit: Int = 100, andOffset offset: Int = 0, completionBlock: @escaping (_ threads: [NCThread]?, _ error: Error?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(nil, NSError(domain: "", code: 0, userInfo: nil))
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "chat/subscribed-threads", withAPIType: .chat, forAccount: account)

        let parameters: [String: Any] = [
            "limit": limit,
            "offfset": offset
        ]

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let error = ocsError?.error {
                completionBlock(nil, error)
            } else if let threads = ocsResponse?.dataArrayDict?.map({ NCThread(dictionary: $0, andAccountId: accountId) }) {
                NCThread.storeOrUpdateThreads(threads)

                NCDatabaseManager.sharedInstance().updateHasThreads(forAccountId: accountId, with: !threads.isEmpty)
                NCDatabaseManager.sharedInstance().updateThreadsLastCheckTimestamp(forAccountId: accountId, with: Int(Date().timeIntervalSince1970))

                let userInfo: [AnyHashable: Any] = [
                    "threads": threads,
                    "accountId": accountId
                ]
                NotificationCenter.default.post(name: .NCUserThreadsUpdated, object: self, userInfo: userInfo)

                completionBlock(threads, nil)
            } else {
                completionBlock(nil, NSError(domain: "", code: 0, userInfo: nil))
            }
        }
    }

    @nonobjc
    public func getThread(for accountId: String, in roomToken: String, threadId: Int, completionBlock: @escaping (_ thread: NCThread?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/threads/\(threadId)", withAPIType: .chat, forAccount: account)

        apiSessionManager.getOcs(urlString, account: account, parameters: nil) { ocs, _ in
            guard let threadDict = ocs?.dataDict as? [String: Any] else {
                completionBlock(nil)
                return
            }

            let thread = NCThread(dictionary: threadDict, andAccountId: accountId)
            NCThread.storeOrUpdateThreads([thread])
            completionBlock(thread)
        }
    }

    @nonobjc
    public func renameThread(with threadTitle: String, for accountId: String, in roomToken: String, threadId: Int, completionBlock: @escaping (_ thread: NCThread?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/threads/\(threadId)", withAPIType: .chat, forAccount: account)

        let parameters: [String: String] = [
            "threadTitle": threadTitle
        ]

        apiSessionManager.putOcs(urlString, account: account, parameters: parameters) { ocs, _ in
            guard let threadDict = ocs?.dataDict as? [String: Any] else {
                completionBlock(nil)
                return
            }

            let thread = NCThread(dictionary: threadDict, andAccountId: accountId)
            NCThread.storeOrUpdateThreads([thread])
            completionBlock(thread)
        }
    }

    @nonobjc
    public func setNotificationLevelForThread(for accountId: String, in roomToken: String, threadId: Int, level: Int, completionBlock: @escaping (_ thread: NCThread?) -> Void) {
        guard let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = roomToken.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else {
            completionBlock(nil)
            return
        }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/threads/\(threadId)/notify", withAPIType: .chat, forAccount: account)

        let parameters: [String: Int] = [
            "level": level
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocs, _ in
            guard let threadDict = ocs?.dataDict as? [String: Any] else {
                completionBlock(nil)
                return
            }

            let thread = NCThread(dictionary: threadDict, andAccountId: accountId)
            NCThread.storeOrUpdateThreads([thread])
            completionBlock(thread)
        }
    }

    // MARK: - Message pinning

    @nonobjc
    @MainActor
    @discardableResult
    public func pinMessage(_ messageId: Int, inRoom token: String, pinUntil until: Int?, forAccount account: TalkAccount) async throws -> NCChatMessage? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(messageId)/pin", withAPIType: .chat, forAccount: account)

        var parameters = [String: Int]()

        if let until {
            parameters["pinUntil"] = until
        }

        let ocsResponse = try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters)

        return NCChatMessage(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func unpinMessage(_ messageId: Int, inRoom token: String, forAccount account: TalkAccount) async throws -> NCChatMessage? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(messageId)/pin", withAPIType: .chat, forAccount: account)

        let ocsResponse = try await apiSessionManager.deleteOcs(urlString, account: account)

        return NCChatMessage(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func unpinMessageForSelf(_ messageId: Int, inRoom token: String, forAccount account: TalkAccount) async throws -> NCChatMessage? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(messageId)/pin/self", withAPIType: .chat, forAccount: account)

        let ocsResponse = try await apiSessionManager.deleteOcs(urlString, account: account)

        return NCChatMessage(dictionary: ocsResponse.dataDict, andAccountId: account.accountId)
    }

    // MARK: - Core

    @nonobjc
    func getAppPasswordOnetime(forServer server: String, withUsername username: String, andOnetimeToken onetimeToken: String, completionBlock: @escaping (_ permanentAppToken: String?) -> Void) {
        let appPasswordRoute = "\(server)/ocs/v2.php/core/getapppassword-onetime"

        let credentialsString = "\(username):\(onetimeToken)"
        let authHeader = "Basic \(credentialsString.data(using: .utf8)!.base64EncodedString())"

        let configuration = URLSessionConfiguration.default
        let apiSessionManager = NCAPISessionManager(configuration: configuration)
        apiSessionManager.requestSerializer.setValue(authHeader, forHTTPHeaderField: "Authorization")
        apiSessionManager.requestSerializer.setValue(NCAppBranding.userAgentForLogin(), forHTTPHeaderField: "User-Agent")

        _ = apiSessionManager.get(appPasswordRoute, parameters: nil, progress: nil) { _, result in
            if let resultDict = result as? [String: AnyObject],
               let ocs = resultDict["ocs"] as? [String: AnyObject],
               let data = ocs["data"] as? [String: AnyObject],
               let apppassword = data["apppassword"] as? String {

                completionBlock(apppassword)
            }

            completionBlock(nil)
        } failure: { _, _ in
            completionBlock(nil)
        }
    }

    // MARK: - Message scheduling

    @nonobjc
    @MainActor
    public func getScheduledMessages(forRoom token: String, forAccount account: TalkAccount) async throws -> [ScheduledMessage] {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/schedule", withAPIType: .chat, forAccount: account)

        let ocsResponse = try await apiSessionManager.getOcs(urlString, account: account)

        guard let dataArrayDict = ocsResponse.dataArrayDict else { throw ApiControllerError.unexpectedOcsResponse }

        return dataArrayDict.compactMap { ScheduledMessage(dictionary: $0, withAccount: account) }
    }

    @nonobjc
    @MainActor
    @discardableResult
    public func scheduleMessage(_ message: String, inRoom token: String, sendAt: Int, replyTo: Int? = nil, silent: Bool? = nil, threadTitle: String? = nil, threadId: Int? = nil, forAccount account: TalkAccount) async throws -> ScheduledMessage? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/schedule", withAPIType: .chat, forAccount: account)

        let parameters: [String: Any?] = [
            "message": message,
            "sendAt": sendAt,
            "replyTo": replyTo,
            "silent": silent,
            "threadTitle": threadTitle,
            "threadId": threadId
        ]

        let result = try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters.compactMapValues { $0 })
        return ScheduledMessage(dictionary: result.dataDict, withAccount: account)
    }

    @nonobjc
    @MainActor
    public func editScheduledMessage(_ messageId: String, withMessage message: String, inRoom token: String, sendAt: Int, silent: Bool? = nil, threadTitle: String? = nil, forAccount account: TalkAccount) async throws -> ScheduledMessage {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/schedule/\(messageId)", withAPIType: .chat, forAccount: account)

        let parameters: [String: Any?] = [
            "message": message,
            "sendAt": sendAt,
            "silent": silent,
            "threadTitle": threadTitle
        ]

        let result = try await apiSessionManager.postOcs(urlString, account: account, parameters: parameters.compactMapValues { $0 })
        guard let updatedMessage = ScheduledMessage(dictionary: result.dataDict, withAccount: account) else { throw ApiControllerError.unexpectedOcsResponse }

        return updatedMessage
    }

    @nonobjc
    @MainActor
    public func deleteScheduledMessage(_ messageId: String, inRoom token: String, forAccount account: TalkAccount) async throws {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/schedule/\(messageId)", withAPIType: .chat, forAccount: account)

        try await apiSessionManager.deleteOcs(urlString, account: account)
    }

    // MARK: - Password policy

    @nonobjc
    @MainActor
    public func validatePassword(password: String, forAccount account: TalkAccount) async throws -> (passed: Bool, reason: String?) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { throw ApiControllerError.preconditionError }

        // Check capabilities directly, otherwise NCSettingsController introduces new dependencies in NotificationServiceExtension
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId),
              !serverCapabilities.passwordPolicyValidateAPIEndpoint.isEmpty
        else { return (true, "") }

        let parameters: [String: String] = [
            "password": password,
            "context": "sharing"
        ]

        let ocsResponse = try await apiSessionManager.postOcs(serverCapabilities.passwordPolicyValidateAPIEndpoint, account: account, parameters: parameters)

        guard let dataDict = ocsResponse.dataDict,
        let passed = dataDict["passed"] as? Bool
        else { throw ApiControllerError.unexpectedOcsResponse }

        let reason = dataDict["reason"] as? String

        return (passed, reason)
    }

    // MARK: - Bots

    @nonobjc
    @MainActor
    public func getBots(forRoom token: String, forAccount account: TalkAccount) async throws -> [Bot] {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "bot/\(encodedToken)", withAPIType: .bots, forAccount: account)

        let ocsResponse = try await apiSessionManager.getOcs(urlString, account: account)

        guard let dataArrayDict = ocsResponse.dataArrayDict else { throw ApiControllerError.unexpectedOcsResponse }

        return dataArrayDict.compactMap { Bot(dictionary: $0) }
    }

    @nonobjc
    @MainActor
    public func enableBot(withId botId: Int, forRoom token: String, forAccount account: TalkAccount) async throws -> Bot? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "bot/\(encodedToken)/\(botId)", withAPIType: .bots, forAccount: account)

        let result = try await apiSessionManager.postOcs(urlString, account: account)
        return Bot(dictionary: result.dataDict)
    }

    @nonobjc
    @MainActor
    public func disableBot(withId botId: Int, forRoom token: String, forAccount account: TalkAccount) async throws -> Bot? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "bot/\(encodedToken)/\(botId)", withAPIType: .bots, forAccount: account)

        let result = try await apiSessionManager.deleteOcs(urlString, account: account)
        return Bot(dictionary: result.dataDict)
    }

    // MARK: - Breakout rooms controller

    @MainActor
    public func requestAssistance(inRoom token: String, forAccount account: TalkAccount) async throws {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "breakout-rooms/\(encodedToken)/request-assistance", withAPIType: .breakoutRooms, forAccount: account)

        try await apiSessionManager.postOcs(urlString, account: account)
    }

    @MainActor
    public func stopRequestingAssistance(inRoom token: String, forAccount account: TalkAccount) async throws {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { throw ApiControllerError.preconditionError }

        let urlString = self.getRequestURL(forEndpoint: "breakout-rooms/\(encodedToken)/request-assistance", withAPIType: .breakoutRooms, forAccount: account)

        try await apiSessionManager.deleteOcs(urlString, account: account)
    }

    // MARK: - Call controller

    @discardableResult
    public func getPeersForCall(inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ peers: [[String: AnyObject]]?, _ error: Error?, _ statusCode: Int) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "call/\(encodedToken)", withAPIType: .call, forAccount: account)

        return apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataArrayDict, ocsError?.error, ocsError?.responseStatusCode ?? 0)
        }
    }

    @discardableResult
    // swiftlint:disable:next function_parameter_count
    public func joinCall(inRoom token: String,
                         withCallFlags flags: CallFlag,
                         joinSilently silently: Bool,
                         joinSilentlyFor silentFor: [String],
                         withRecordingConsent recordingConsent: Bool,
                         forAccount account: TalkAccount,
                         completionBlock: @escaping (_ error: Error?, _ statusCode: Int) -> Void) -> URLSessionTask? {

        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "call/\(encodedToken)", withAPIType: .call, forAccount: account)

        var parameters: [String: Any] = [
            "flags": flags.rawValue,
            "recordingConsent": recordingConsent,
            "silent": silently
        ]

        if !silentFor.isEmpty {
            parameters["silentFor"] = silentFor
        }

        return apiSessionManager.postOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error, ocsError?.responseStatusCode ?? 0)
        }
    }

    @discardableResult
    public func leaveCall(inRoom token: String, forAllParticipants allParticipants: Bool, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "call/\(encodedToken)", withAPIType: .call, forAccount: account)

        return apiSessionManager.deleteOcs(urlString, account: account, parameters: ["all": allParticipants]) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    @nonobjc
    @discardableResult
    public func sendCallNotification(toParticipant participant: String?, inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "call/\(encodedToken)", withAPIType: .call, forAccount: account)

        var parameters: [String: Any] = [:]

        if let participant {
            parameters["attendeeId"] = participant
        }

        return apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    // MARK: - Server capabilities

    @discardableResult
    public func getServerCapabilities(forServer server: String, completionBlock: @escaping (_ serverCapabilities: [AnyHashable: Any]?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        let urlString = "\(server)/ocs/v1.php/cloud/capabilities"

        return defaultAPISessionManager.getOcs(urlString, account: nil, parameters: ["format": "json"]) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError?.error)
        }
    }

    @discardableResult
    public func getServerCapabilities(forAccount account: TalkAccount, completionBlock: @escaping (_ serverCapabilities: [AnyHashable: Any]?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return nil }

        let urlString = "\(account.server)/ocs/v1.php/cloud/capabilities"

        return apiSessionManager.getOcs(urlString, account: account, parameters: ["format": "json"]) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError?.error)
        }
    }

    // MARK: - Server notification

    @nonobjc
    @discardableResult
    public func getServerNotification(withId notificationId: Int, forAccount account: TalkAccount, completionBlock: @escaping (_ notification: NCNotification?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        // This method is currently only used in tests as NSE is using the endpoint directly
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return nil }

        let urlString = "\(account.server)/ocs/v2.php/apps/notifications/api/v2/notifications/\(notificationId)"

        return apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(NCNotification(dictionary: ocsResponse?.dataDict), ocsError?.error)
        }
    }

    @nonobjc
    @MainActor
    public func deleteServerNotification(withId notificationId: Int, forAccount account: TalkAccount) async throws {
        // This method is currently only used in tests
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { throw ApiControllerError.preconditionError }

        let urlString = "\(account.server)/ocs/v2.php/apps/notifications/api/v2/notifications/\(notificationId)"

        try await apiSessionManager.deleteOcs(urlString, account: account)
    }

    public func executeNotificationAction(_ action: NCNotificationAction, forAccount account: TalkAccount, completionBlock: ((_ error: Error?) -> Void)?) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        guard let actionLink = action.actionLink else {
            print("Trying to execute notification action without actionLink")
            completionBlock?(NSError(domain: NSCocoaErrorDomain, code: 0))

            return
        }

        let success = { (_ task: URLSessionDataTask, _ responseObject: Any?) in
            if let completionBlock {
                completionBlock(nil)
            }
        }

        let failure = { (_ task: URLSessionDataTask?, _ error: any Error) in
            if let completionBlock {
                completionBlock(error)
            }
        }

        switch action.actionType {
        case .kNotificationActionTypeGet:
            apiSessionManager.get(actionLink, parameters: nil, progress: nil, success: success, failure: failure)
        case .kNotificationActionTypePut:
            apiSessionManager.put(actionLink, parameters: nil, success: success, failure: failure)
        case .kNotificationActionTypePost:
            apiSessionManager.post(actionLink, parameters: nil, progress: nil, success: success, failure: failure)
        case .kNotificationActionTypeDelete:
            apiSessionManager.delete(actionLink, parameters: nil, success: success, failure: failure)
        default:
            print("Trying to execute non-supported notification action type")
            completionBlock?(NSError(domain: NSCocoaErrorDomain, code: 0))
        }
    }

    @discardableResult
    public func checkNotificationExistance(withIds notificationIds: [Int], forAccount account: TalkAccount, completionBlock: @escaping (_ notification: [Int]?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return nil }

        let urlString = "\(account.server)/ocs/v2.php/apps/notifications/api/v2/notifications/exists"

        return apiSessionManager.postOcs(urlString, account: account, parameters: ["ids": notificationIds]) { ocsResponse, ocsError in
            if let intArray = ocsResponse?.ocsDict?["data"] as? [Int] {
                completionBlock(intArray, nil)
            } else {
                completionBlock(nil, ocsError)
            }
        }
    }

    // MARK: - Contacts controller

    @discardableResult
    public func searchContacts(forAccount account: TalkAccount, withPhoneNumbers phoneNumbers: [String: [String]], completionBlock: @escaping (_ contacts: [String: String]?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return nil }

        let urlString = "\(account.server)/ocs/v2.php/cloud/users/search/by-phone"
        let parameters: [String: Any] = [
            "location": Locale.current.region?.identifier ?? "",
            "search": phoneNumbers
        ]

        // Ignore status code for now https://github.com/nextcloud/server/pull/26679
        return apiSessionManager.postOcs(urlString, account: account, parameters: parameters, checkResponseStatusCode: false) { ocsResponse, ocsError in
            if let contactsDict = ocsResponse?.dataDict as? [String: String] {
                completionBlock(contactsDict, ocsError?.error)
            } else {
                completionBlock(nil, ocsError?.error)
            }
        }
    }

    @discardableResult
    public func getContacts(forAccount account: TalkAccount, forRoom room: String?, forGroupRoom groupRoom: Bool, withSearchParam searchParam: String?, completionBlock: @escaping (_ contacts: [NCUser]?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return nil }

        let urlString = "\(account.server)/ocs/v2.php/core/autocomplete/get"

        var shareTypes = [NCShareType.user.rawValue]
        if groupRoom, NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityInviteGroupsAndMails, forAccountId: account.accountId) {
            shareTypes.append(NCShareType.group.rawValue)
            shareTypes.append(NCShareType.email.rawValue)

            if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityCirclesSupport, forAccountId: account.accountId) {
                shareTypes.append(NCShareType.circle.rawValue)
            }

            if NCDatabaseManager.sharedInstance().serverCanInviteFederatedUsersforAccountId(account.accountId) {
                shareTypes.append(NCShareType.remote.rawValue)
            }
        }

        let parameters: [String: Any] = [
            "format": "json",
            "search": searchParam ?? "",
            "limit": "50",
            "itemType": "call",
            "itemId": room ?? "new",
            "shareTypes": shareTypes
        ]

        return apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let contactsDict = ocsResponse?.dataArrayDict {
                let contacts = contactsDict
                    .compactMap( { NCUser(dictionary: $0) })
                    .filter({ !($0.userId == account.userId && $0.source as String == kParticipantTypeUser) })

                completionBlock(contacts, ocsError?.error)
            } else {
                completionBlock(nil, ocsError?.error)
            }
        }
    }

    // TODO: Can be combined with 'getContacts(forAccount:)' at some point
    @discardableResult
    public func searchUsers(forAccount account: TalkAccount, withSearchParam searchParam: String?, completionBlock: @escaping (_ contacts: [NCUser]?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return nil }

        let urlString = "\(account.server)/ocs/v2.php/core/autocomplete/get"

        let parameters: [String: Any] = [
            "format": "json",
            "search": searchParam ?? "",
            "limit": "20"
        ]

        return apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let contactsDict = ocsResponse?.dataArrayDict {
                let contacts = contactsDict
                    .compactMap( { NCUser(dictionary: $0) })
                    .filter({ !($0.userId == account.userId && $0.source as String == kParticipantTypeUser) })

                completionBlock(contacts, ocsError?.error)
            } else {
                completionBlock(nil, ocsError?.error)
            }
        }
    }

    // MARK: - Translations controller

    @nonobjc
    public func getAvailableTranslations(forAccount account: TalkAccount, completionBlock: @escaping (_ translations: [NCTranslation]?, _ langugageDetection: Bool, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/translation/languages"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            if let translationDict = ocsResponse?.dataDict {
                var availableTranslations: [NCTranslation]?

                if let translations = translationDict["languages"] as? [[String: Any]] {
                    availableTranslations = NCDatabaseManager.sharedInstance().translations(fromTranslationsArray: translations)
                }

                completionBlock(availableTranslations, translationDict["languageDetection"] as? Bool ?? false, ocsError?.error)
            } else {
                completionBlock(nil, false, ocsError?.error)
            }
        }
    }

    @nonobjc
    public func translateMessage(_ message: String, fromLanguage from: String?, toLanguage to: String, forAccount account: TalkAccount, completionBlock: @escaping (_ translationDict: [String: Any]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/translation/translate"

        var parameters = [
            "text": message,
            "toLanguage": to
        ]

        if let from, !from.isEmpty {
            parameters["fromLanguage"] = from
        }

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict ?? ocsError?.dataDict, ocsError?.error)
        }
    }

    // MARK: - Reactions controller

    @nonobjc
    public func addReaction(_ reaction: String, toMessage messageId: Int, inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ reactionsDict: [String: Any]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "reaction/\(encodedToken)/\(messageId)", withAPIType: .reactions, forAccount: account)

        apiSessionManager.postOcs(urlString, account: account, parameters: ["reaction": reaction]) { ocsResponse, ocsError in
            if let ocsResponse {
                // When there are no elements, the server returns an empty array instead of an empty dictionary
                completionBlock(ocsResponse.dataDict ?? [:], nil)
            } else {
                completionBlock(nil, ocsError)
            }
        }
    }

    @nonobjc
    public func removeReaction(_ reaction: String, fromMessage messageId: Int, inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ reactionsDict: [String: Any]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "reaction/\(encodedToken)/\(messageId)", withAPIType: .reactions, forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account, parameters: ["reaction": reaction]) { ocsResponse, ocsError in
            if let ocsResponse {
                // When there are no elements, the server returns an empty array instead of an empty dictionary
                completionBlock(ocsResponse.dataDict ?? [:], nil)
            } else {
                completionBlock(nil, ocsError)
            }
        }
    }

    @nonobjc
    public func getReactions(_ reaction: String?, fromMessage messageId: Int, inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ reactionsDict: [String: Any]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "reaction/\(encodedToken)/\(messageId)", withAPIType: .reactions, forAccount: account)
        var parameters: [String: Any] = [:]

        if let reaction {
            parameters["reaction"] = reaction
        }

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let ocsResponse {
                // When there are no elements, the server returns an empty array instead of an empty dictionary
                completionBlock(ocsResponse.dataDict ?? [:], nil)
            } else {
                completionBlock(nil, ocsError)
            }
        }
    }

    // MARK: - Reference handling

    public func getReference(forUrlString referenceUrl: String, forAccount account: TalkAccount, completionBlock: @escaping (_ referenceDict: [String: Any]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/references/resolve"

        apiSessionManager.getOcs(urlString, account: account, parameters: ["reference": referenceUrl]) { ocsResponse, ocsError in
            if let ocsResponse {
                // When there's no data, the server returns an empty array instead of a dictionary
                completionBlock(ocsResponse.dataDict?["references"] as? [String: [String: AnyObject]] ?? [:], nil)
            } else {
                completionBlock(nil, ocsError)
            }
        }
    }

    // MARK: - Recording

    public func startRecording(inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "recording/\(encodedToken)", withAPIType: .recording, forAccount: account)

        // Status 1 -> Video recording
        // Status 2 -> Audio recording (not supported for now)
        let parameters = ["status": 1]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func stopRecording(inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "recording/\(encodedToken)", withAPIType: .recording, forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func dismissStoredRecordingNotification(withTimestamp timestamp: String, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "recording/\(encodedToken)/notification", withAPIType: .recording, forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account, parameters: ["timestamp": timestamp]) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    public func shareStoredRecording(withTimestamp timestamp: String, withFileId fileId: String, forRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "recording/\(encodedToken)/share-chat", withAPIType: .recording, forAccount: account)
        let parameters = [
            "timestamp": timestamp,
            "fileId": fileId
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError?.error)
        }
    }

    // MARK: - Remind me later

    @nonobjc
    public func setReminder(forMessage message: NCChatMessage, withTimestamp timestamp: Int, completionBlock: @escaping (_ error: OcsError?) -> Void) {
        guard let account = message.account,
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = message.token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(message.messageId)/reminder", withAPIType: .chat, forAccount: account)

        apiSessionManager.postOcs(urlString, account: account, parameters: ["timestamp": timestamp]) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @nonobjc
    public func deleteReminder(forMessage message: NCChatMessage, completionBlock: @escaping (_ error: OcsError?) -> Void) {
        guard let account = message.account,
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = message.token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(message.messageId)/reminder", withAPIType: .chat, forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @nonobjc
    public func getReminder(forMessage message: NCChatMessage, completionBlock: @escaping (_ responseDict: [String: Any]?, _ error: OcsError?) -> Void) {
        guard let account = message.account,
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = message.token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(message.messageId)/reminder", withAPIType: .chat, forAccount: account)

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError)
        }
    }

    // MARK: - Settings

    @nonobjc
    private func setUserSetting(withKey key: String, toValue value: Any, forAccount account: TalkAccount, completionBlock: @escaping (_ error: OcsError?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "settings/user", withAPIType: .settings, forAccount: account)
        let parameters: [String: Any] = [
            "key": key,
            "value": value
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @nonobjc
    public func setReadStatusPrivacySettingEnabled(_ enabled: Bool, forAccount account: TalkAccount, completionBlock: @escaping (_ error: OcsError?) -> Void) {
        self.setUserSetting(withKey: "read_status_privacy", toValue: enabled, forAccount: account) { error in
            completionBlock(error)
        }
    }

    @nonobjc
    public func setTypingPrivacySettingEnabled(_ enabled: Bool, forAccount account: TalkAccount, completionBlock: @escaping (_ error: OcsError?) -> Void) {
        self.setUserSetting(withKey: "typing_privacy", toValue: enabled, forAccount: account) { error in
            completionBlock(error)
        }
    }

    // MARK: - Push Notifications

    public func subscribeAccount(_ account: TalkAccount, withPublicKey publicKey: Data, toNextcloudServerWithCompletionBlock completionBlock: @escaping (_ responseDict: [String: Any]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let devicePublicKey = String(data: publicKey, encoding: .utf8)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/apps/notifications/api/v2/push"
        let parameters = [
            "pushTokenHash": NCKeyChainController.sharedInstance().pushTokenSHA512(),
            "devicePublicKey": devicePublicKey,
            "proxyServer": pushNotificationServer
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError)
        }
    }

    public func unsubscribeAccount(_ account: TalkAccount, fromNextcloudServerWithCompletionBlock completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/apps/notifications/api/v2/push"

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    public func subscribeAccount(_ account: TalkAccount, toPushServerWithCompletionBlock completionBlock: @escaping (_ error: Error?) -> Void) {
        let urlString = "\(pushNotificationServer)/devices"
        let parameters = [
            "pushToken": NCKeyChainController.sharedInstance().combinedPushToken(),
            "deviceIdentifier": account.deviceIdentifier,
            "deviceIdentifierSignature": account.deviceSignature,
            "userPublicKey": account.userPublicKey
        ]

        NCPushProxySessionManager.shared.post(urlString, parameters: parameters, progress: nil) { _, _ in
            completionBlock(nil)
        } failure: { _, error in
            completionBlock(error)
        }
    }

    public func unsubscribeAccount(_ account: TalkAccount, fromPushServerWithCompletionBlock completionBlock: @escaping (_ error: Error?) -> Void) {
        let urlString = "\(pushNotificationServer)/devices"
        let parameters = [
            "deviceIdentifier": account.deviceIdentifier,
            "deviceIdentifierSignature": account.deviceSignature,
            "userPublicKey": account.userPublicKey
        ]

        NCPushProxySessionManager.shared.delete(urlString, parameters: parameters) { _, _ in
            completionBlock(nil)
        } failure: { _, error in
            completionBlock(error)
        }
    }

    // MARK: - Remote wipe

    public func checkWipeStatus(forAccount account: TalkAccount, completionBlock: @escaping (_ wipe: Bool, _ error: Error?) -> Void) {
        guard let token = NCKeyChainController.sharedInstance().token(forAccountId: account.accountId)
        else {
            completionBlock(false, NSError(domain: NSCocoaErrorDomain, code: 0))
            return
        }

        let urlString = "\(account.server)/index.php/core/wipe/check"

        defaultAPISessionManager.postOcs(urlString, account: account, parameters: ["token": token]) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.responseDict?["wipe"] != nil, ocsError?.error)
        }
    }

    public func confirmWipe(forAccount account: TalkAccount, completionBlock: ((_ error: Error?) -> Void)?) {
        guard let token = NCKeyChainController.sharedInstance().token(forAccountId: account.accountId)
        else {
            completionBlock?(NSError(domain: NSCocoaErrorDomain, code: 0))
            return
        }

        let urlString = "\(account.server)/index.php/core/wipe/success"

        defaultAPISessionManager.postOcs(urlString, account: account, parameters: ["token": token]) { _, ocsError in
            completionBlock?(ocsError?.error)
        }
    }

    // MARK: - AppStore info

    public func getAppStoreAppId(withCompletionBlock completionBlock: @escaping (_ appId: String?, _ error: Error?) -> Void) {
        let urlString = "http://itunes.apple.com/lookup?bundleId=\(bundleIdentifier)"

        defaultAPISessionManager.get(urlString, parameters: nil, progress: nil, success: { _, responseObject in
            if let responseDict = responseObject as? [String: Any], let results = responseDict["results"] as? [[String: Any]], let firstResult = results.first {
                if let trackId = firstResult["trackId"] as? Int {
                    completionBlock(String(trackId), nil)
                    return
                }
            }

            completionBlock(nil, NSError(domain: NSCocoaErrorDomain, code: 0))
        }, failure: { _, error in
            completionBlock(nil, error)
        })
    }

    // MARK: - Chat controller

    @discardableResult
    // swiftlint:disable:next function_parameter_count
    public func receiveChatMessages(ofRoom token: String,
                                    fromLastMessageId messageId: Int,
                                    inThread threadId: Int,
                                    history: Bool,
                                    includeLastMessage: Bool,
                                    timeout: Bool,
                                    limit: Int,
                                    lastCommonReadMessage: Int,
                                    setReadMarker: Bool,
                                    markNotificationsAsRead: Bool,
                                    forAccount account: TalkAccount,
                                    completionBlock: @escaping (_ messages: [[String: Any]]?, _ lastKnownMessage: Int, _ lastCommonReadMessage: Int, _ error: Error?, _ statusCode: Int) -> Void) -> URLSessionDataTask? {

        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)", withAPIType: .chat, forAccount: account)

        var limitParameter = limit

        if limitParameter <= 0 {
            // Ensure we don't try to request an invalid number of messages (although there's a limit server side)
            limitParameter = kReceivedChatMessagesLimit
        }

        let parameters: [String: Any] = [
            "lookIntoFuture": history ? 0 : 1,
            "limit": min(kReceivedChatMessagesLimit, limitParameter),
            "timeout": timeout ? 30 : 0,
            "lastKnownMessageId": messageId,
            "lastCommonReadId": lastCommonReadMessage,
            "setReadMarker": setReadMarker ? 1 : 0,
            "includeLastKnown": includeLastMessage ? 1 : 0,
            "markNotificationsAsRead": markNotificationsAsRead ? 1 : 0,
            "threadId": threadId
        ]

        let apiSessionManager: NCAPISessionManager?

        if timeout {
            apiSessionManager = self.getLongPollingAPISessionManager(forAccountId: account.accountId)
        } else {
            apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        }

        guard let apiSessionManager else { return nil }

        return apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let ocsResponse, let messageDict = ocsResponse.dataArrayDict {
                // TODO: Directly return NCChatMessage objects
                // let messages = messageDict.compactMap( { NCChatMessage(dictionary: $0, andAccountId: account.accountId) })

                let headerLastKnownMessage = Int(ocsResponse.value(forHTTPHeaderField: "x-chat-last-given")) ?? -1
                let headerLastCommonRead = Int(ocsResponse.value(forHTTPHeaderField: "x-chat-last-common-read")) ?? -1

                completionBlock(messageDict, headerLastKnownMessage, headerLastCommonRead, ocsError?.error, ocsResponse.responseStatusCode)
            } else {
                completionBlock(nil, -1, -1, ocsError?.error, ocsError?.responseStatusCode ?? 0)
            }
        }
    }

    @discardableResult
    // swiftlint:disable:next function_parameter_count
    public func sendChatMessage(_ message: String,
                                toRoom token: String,
                                threadTitle: String?,
                                replyTo: Int,
                                referenceId: String?,
                                silently: Bool,
                                forAccount account: TalkAccount,
                                completionBlock: @escaping (_ error: Error?) -> Void) -> URLSessionDataTask? {

        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)", withAPIType: .chat, forAccount: account)

        var parameters: [String: Any] = [
            "message": message
        ]

        if replyTo > -1 {
            parameters["replyTo"] = replyTo
        }

        if let referenceId {
            parameters["referenceId"] = referenceId
        }

        if silently {
            parameters["silent"] = silently
        }

        if let threadTitle {
            parameters["threadTitle"] = threadTitle
        }

        return apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @nonobjc
    @discardableResult
    public func deleteChatMessage(inRoom token: String, withMessageId messageId: Int, forAccount account: TalkAccount, completionBlock: @escaping (_ message: [String: Any]?, _ error: Error?, _ statusCode: Int) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(messageId)", withAPIType: .chat, forAccount: account)

        return apiSessionManager.deleteOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError, ocsResponse?.responseStatusCode ?? ocsError?.responseStatusCode ?? 0)
        }
    }

    @nonobjc
    @discardableResult
    public func editChatMessage(inRoom token: String, withMessageId messageId: Int, withMessage message: String, forAccount account: TalkAccount, completionBlock: @escaping (_ message: [String: Any]?, _ error: Error?, _ statusCode: Int) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(messageId)", withAPIType: .chat, forAccount: account)

        return apiSessionManager.putOcs(urlString, account: account, parameters: ["message": message]) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError, ocsResponse?.responseStatusCode ?? ocsError?.responseStatusCode ?? 0)
        }
    }

    @nonobjc
    @discardableResult
    public func clearChatHistory(inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ message: [String: Any]?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)", withAPIType: .chat, forAccount: account)

        return apiSessionManager.deleteOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError)
        }
    }

    @nonobjc
    @discardableResult
    public func shareRichObject(_ richObject: [AnyHashable: Any], inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/share", withAPIType: .chat, forAccount: account)

        return apiSessionManager.postOcs(urlString, account: account, parameters: richObject) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @discardableResult
    public func setChatReadMarker(_ lastReadMessage: Int, inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/read", withAPIType: .chat, forAccount: account)

        return apiSessionManager.postOcs(urlString, account: account, parameters: ["lastReadMessage": lastReadMessage]) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @discardableResult
    public func markChatAsUnread(inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/read", withAPIType: .chat, forAccount: account)

        return apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @nonobjc
    @discardableResult
    public func getSharedItemsOverview(inRoom token: String, withLimit limit: Int, forAccount account: TalkAccount, completionBlock: @escaping (_ sharedItemsOverview: [String: [NCChatMessage]]?, _ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/share/overview", withAPIType: .chat, forAccount: account)
        var parameters: [String: Any] = [:]

        if limit > -1 {
            parameters["limit"] = limit
        }

        return apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let dataDict = ocsResponse?.dataDict as? [String: [[String: Any]]] {
                // e.g. ["location": [message1, message2, ...], "audio": ...]
                var result: [String: [NCChatMessage]] = [:]

                for (key, value) in dataDict {
                    result[key] = value.compactMap({ NCChatMessage(dictionary: $0) })
                }

                completionBlock(result, nil)
            } else {
                completionBlock(nil, ocsError)
            }
        }
    }

    @nonobjc
    @discardableResult
    // swiftlint:disable:next function_parameter_count
    public func getSharedItems(ofType type: String, fromLastMessageId messageId: Int, inRoom token: String, withLimit limit: Int, forAccount account: TalkAccount, completionBlock: @escaping (_ sharedItems: [NCChatMessage]?, _ lastKnownMessageId: Int, _ error: Error?) -> Void) -> URLSessionDataTask? {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return nil }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/share", withAPIType: .chat, forAccount: account)
        var parameters: [String: Any] = [
            "objectType": type
        ]

        if messageId > -1 {
            parameters["lastKnownMessageId"] = messageId
        }

        if limit > -1 {
            parameters["limit"] = limit
        }

        return apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            if let dataDict = ocsResponse?.dataDict as? [String: [String: Any]] {
                let headerLastKnownMessage = Int(ocsResponse?.value(forHTTPHeaderField: "x-chat-last-given")) ?? -1
                completionBlock(dataDict.compactMap({ NCChatMessage(dictionary: $0.value) }), headerLastKnownMessage, nil)
            } else {
                completionBlock(nil, -1, ocsError)
            }
        }
    }

    public func getMessageContext(inRoom token: String, forMessageId messageId: Int, inThread threadId: Int, withLimit limit: Int = 50, forAccount account: TalkAccount, completionBlock: @escaping (_ messages: [NCChatMessage]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "chat/\(encodedToken)/\(messageId)/context", withAPIType: .chat, forAccount: account)

        var parameters: [String: Any] = [
            "limit": limit
        ]

        if threadId > 0 {
            parameters["threadId"] = threadId
        }

        apiSessionManager.getOcs(urlString, account: account, parameters: parameters) { ocs, ocsError in
            if let dataArrayDict = ocs?.dataArrayDict {
                completionBlock(dataArrayDict.map({ NCChatMessage(dictionary: $0, andAccountId: account.accountId) }), nil)
            } else {
                completionBlock(nil, ocsError)
            }
        }
    }

    // MARK: - Polls controller

    @nonobjc
    // swiftlint:disable:next function_parameter_count
    public func createPoll(withQuestion question: String,
                           withOptions options: [String],
                           withResultMode resultMode: NCPollResultMode,
                           withMaxVotes maxVotes: Int,
                           asDraft draft: Bool,
                           inRoom token: String,
                           forAccount account: TalkAccount,
                           completionBlock: @escaping (_ poll: NCPoll, _ error: Error?) -> Void) {

        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "poll/\(encodedToken)", withAPIType: .polls, forAccount: account)

        let parameters: [String: Any] = [
            "question": question,
            "options": options,
            "resultMode": resultMode.rawValue,
            "draft": draft,
            "maxVotes": maxVotes
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            completionBlock(NCPoll.initWithPollDictionary(ocsResponse?.dataDict), ocsError)
        }
    }

    @nonobjc
    public func getPoll(withId pollId: Int, inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ poll: NCPoll?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "poll/\(encodedToken)/\(pollId)", withAPIType: .polls, forAccount: account)

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(NCPoll.initWithPollDictionary(ocsResponse?.dataDict), ocsError)
        }
    }

    @nonobjc
    // swiftlint:disable:next function_parameter_count
    public func editPollDraft(withId draftId: Int,
                              withQuestion question: String,
                              withOptions options: [String],
                              withResultMode resultMode: NCPollResultMode,
                              withMaxVotes maxVotes: Int,
                              inRoom token: String,
                              forAccount account: TalkAccount,
                              completionBlock: @escaping (_ poll: NCPoll, _ error: Error?) -> Void) {

        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "poll/\(encodedToken)/draft/\(draftId)", withAPIType: .polls, forAccount: account)

        let parameters: [String: Any] = [
            "question": question,
            "options": options,
            "resultMode": resultMode.rawValue,
            "maxVotes": maxVotes
        ]

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { ocsResponse, ocsError in
            completionBlock(NCPoll.initWithPollDictionary(ocsResponse?.dataDict), ocsError)
        }
    }

    @nonobjc
    public func getPollDrafts(inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ polls: [NCPoll]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "poll/\(encodedToken)/drafts", withAPIType: .polls, forAccount: account)

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, ocsError in
            let drafts = ocsResponse?.dataArrayDict?.compactMap({ NCPoll.initWithPollDictionary($0) })
            completionBlock(drafts, ocsError)
        }
    }

    @nonobjc
    public func voteOnPoll(withId pollId: Int, inRoom token: String, withOptions options: [Int], forAccount account: TalkAccount, completionBlock: @escaping (_ poll: NCPoll?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "poll/\(encodedToken)/\(pollId)", withAPIType: .polls, forAccount: account)

        apiSessionManager.postOcs(urlString, account: account, parameters: ["optionIds": options]) { ocsResponse, ocsError in
            completionBlock(NCPoll.initWithPollDictionary(ocsResponse?.dataDict), ocsError)
        }
    }

    @nonobjc
    public func closePoll(withId pollId: Int, inRoom token: String, forAccount account: TalkAccount, completionBlock: @escaping (_ poll: NCPoll?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = self.getRequestURL(forEndpoint: "poll/\(encodedToken)/\(pollId)", withAPIType: .polls, forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { ocsResponse, ocsError in
            completionBlock(NCPoll.initWithPollDictionary(ocsResponse?.dataDict), ocsError)
        }
    }

    // MARK: Dav client

    internal func serverFilePath(forFileName fileName: String, forAccount account: TalkAccount) -> String? {
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        else { return nil }

        return "\(serverCapabilities.attachmentsFolder)/\(fileName)"
    }

    internal func serverFileURL(forfilePath filePath: String, forAccount account: TalkAccount) -> String? {
        return "\(account.server)\(self.filesPath(forAccount: account))\(filePath)"
    }

    internal func attachmentFolderServerURL(forAccount account: TalkAccount) -> String? {
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        else { return nil }

        return "\(account.server)\(self.filesPath(forAccount: account))\(serverCapabilities.attachmentsFolder)"
    }

    internal func alternativeName(forFileName fileName: String, isOriginal: Bool) -> String {
        // TODO: Move to swift foundation methods

        let fileExtension = (fileName as NSString).pathExtension
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension
        var alternativeName = nameWithoutExtension
        var newSuffix = " (1)"

        if !isOriginal {
            // Check if the name ends with ` (n)`
            // swiftlint:disable:next force_try
            let regex = try! NSRegularExpression(pattern: " \\((\\d+)\\)$", options: .caseInsensitive)
            if let match = regex.firstMatch(in: nameWithoutExtension, range: .init(location: 0, length: nameWithoutExtension.count)),
                let fullSuffixRange = Range(match.range(at: 0), in: nameWithoutExtension),
                let numberSuffixRange = Range(match.range(at: 1), in: nameWithoutExtension) {

                let suffixNumber = Int(nameWithoutExtension[numberSuffixRange]) ?? 1
                newSuffix = " (\(suffixNumber + 1))"
                alternativeName = nameWithoutExtension.replacingCharacters(in: fullSuffixRange, with: "")
            }
        }

        alternativeName = "\(alternativeName)\(newSuffix)"

        if !fileExtension.isEmpty {
            alternativeName = "\(alternativeName).\(fileExtension)"
        }

        return alternativeName
    }

    public func readFolder(forAccount account: TalkAccount, atPath path: String?, withDepth depth: String, completionBlock: @escaping (_ items: [NKFile]?, _ error: Error?) -> Void) {
        self.setupNCCommunication(forAccount: account)

        let serverUrlString = "\(account.server)\(self.filesPath(forAccount: account))/\(path ?? "")"

        // We don't need all properties, so we limit the request to the needed ones to reduce size and processing time
        let body = """
<?xml version=\"1.0\" encoding=\"UTF-8\"?>\
        <d:propfind xmlns:d=\"DAV:\" xmlns:oc=\"http://owncloud.org/ns\" xmlns:nc=\"http://nextcloud.org/ns\">\
            <d:prop>\
                <d:getlastmodified />\
                <d:getcontenttype />\
                <d:resourcetype />\
                <fileid xmlns=\"http://owncloud.org/ns\"/>\
                <is-encrypted xmlns=\"http://nextcloud.org/ns\"/>\
                <has-preview xmlns=\"http://nextcloud.org/ns\"/>\
            </d:prop>\
        </d:propfind>
"""

        let options = NKRequestOptions(timeout: TimeInterval(60), queue: .main)
        NextcloudKit.shared.readFileOrFolder(serverUrlFileName: serverUrlString, depth: depth, showHiddenFiles: false, includeHiddenFiles: [], requestBody: body.data(using: .utf8), options: options) { _, files, _, error in
            if error.errorCode == 0 {
                completionBlock(files, nil)
            } else {
                completionBlock(nil, NSError(domain: NSURLErrorDomain, code: error.errorCode))
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    public func shareFileOrFolder(forAccount account: TalkAccount, atPath path: String, toRoom token: String, withTalkMetaData talkMetaData: [String: Any]?, withReferenceId referenceId: String?, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/apps/files_sharing/api/v1/shares"

        var parameters: [String: Any] = [
            "path": path,
            "shareType": 10,
            "shareWith": token
        ]

        if let referenceId {
            parameters["referenceId"] = referenceId
        }

        if let talkMetaData, let jsonData = try? JSONSerialization.data(withJSONObject: talkMetaData), let jsonString = String(data: jsonData, encoding: .utf8) {
            parameters["talkMetaData"] = jsonString
        }

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            if let ocsError {
                // Do not return error when re-sharing a file or folder.
                if ocsError.responseStatusCode != 403 {
                    completionBlock(ocsError)
                    return
                }
            }

            completionBlock(nil)
        }
    }

    func uniqueNameForFileUpload(withName fileName: String, isOriginalName: Bool, forAccount account: TalkAccount, completionBlock: @escaping (_ fileServerURL: String?, _ fileServerPath: String?, _ errorCode: Int, _ errorDescription: String?) -> Void) {
        self.setupNCCommunication(forAccount: account)

        guard let fileServerPath = self.serverFilePath(forFileName: fileName, forAccount: account),
              let fileServerURL = self.serverFileURL(forfilePath: fileServerPath, forAccount: account)
        else { return }

        let options = NKRequestOptions(timeout: TimeInterval(60), queue: .main)
        NextcloudKit.shared.readFileOrFolder(serverUrlFileName: fileServerURL, depth: "0", showHiddenFiles: true, includeHiddenFiles: [], requestBody: nil, options: options) { _, files, _, error in
            if error.errorCode == 0, files.count == 1 {
                // File already exists
                let alternativeName = self.alternativeName(forFileName: fileName, isOriginal: isOriginalName)
                self.uniqueNameForFileUpload(withName: alternativeName, isOriginalName: false, forAccount: account, completionBlock: completionBlock)
            } else if error.errorCode == 404 {
                // File does not exist
                completionBlock(fileServerURL, fileServerPath, 0, nil)
            } else {
                print("Error checking file name: \(error.errorDescription)")
                completionBlock(nil, nil, error.errorCode, error.errorDescription)
            }
        }
    }

    func checkOrCreateAttachmentFolder(forAccount account: TalkAccount, completionBlock: @escaping (_ created: Bool, _ statusCode: Int) -> Void) {
        self.setupNCCommunication(forAccount: account)

        guard let attachmentFolderServerURL = self.attachmentFolderServerURL(forAccount: account)
        else { return }

        let options = NKRequestOptions(timeout: TimeInterval(60), queue: .main)
        NextcloudKit.shared.readFileOrFolder(serverUrlFileName: attachmentFolderServerURL, depth: "0", showHiddenFiles: true, includeHiddenFiles: [], requestBody: nil, options: options) { _, _, _, error in
            if error.errorCode == 404 {
                // Attachment folder does not exist
                NextcloudKit.shared.createFolder(serverUrlFileName: attachmentFolderServerURL, options: options) { _, _, _, error in
                    completionBlock(error.errorCode == 0, error.errorCode)
                }
            } else {
                print("Error checking attachment folder: \(error.errorDescription)")
                completionBlock(false, error.errorCode)
            }
        }
    }

    // MARK: - User actions

    @nonobjc
    public func getUserActions(forUser userId: String, forAccount account: TalkAccount, completionBlock: @escaping (_ actions: [String: Any]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/hovercard/v1/\(encodedUserId)"

        apiSessionManager.getOcs(urlString, account: account, parameters: ["format": "json"]) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError)
        }
    }

    // MARK: - User profile

    public func getUserProfile(forAccount account: TalkAccount, completionBlock: @escaping (_ userProfile: [String: Any]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/cloud/user"

        apiSessionManager.getOcs(urlString, account: account, parameters: ["format": "json"]) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.dataDict, ocsError)
        }
    }

    @nonobjc
    public func getUserProfileEditableFields(forAccount account: TalkAccount, completionBlock: @escaping (_ userProfileEditableFields: [String]?, _ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/cloud/user/fields"

        apiSessionManager.getOcs(urlString, account: account, parameters: ["format": "json"]) { ocsResponse, ocsError in
            completionBlock(ocsResponse?.ocsDict?["data"] as? [String], ocsError)
        }
    }

    @nonobjc
    public func setUserProfileField(_ field: String, withValue value: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedUserId = account.userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/cloud/users/\(encodedUserId)"
        let parameters = [
            "format": "json",
            "key": field,
            "value": value
        ]

        // Ignore status code for now https://github.com/nextcloud/server/pull/26679
        apiSessionManager.putOcs(urlString, account: account, parameters: parameters, checkResponseStatusCode: false) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @nonobjc
    public func setUserProfileImage(_ image: UIImage, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let imageData = image.jpegData(compressionQuality: 0.7)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/apps/spreed/temp-user-avatar"

        apiSessionManager.post(urlString, parameters: nil) { formData in
            formData.appendPart(withFileData: imageData, name: "files[]", fileName: "avatar.jpg", mimeType: "image/jpeg")
        } progress: { _ in
        } success: { _, _ in
            completionBlock(nil)
        } failure: { _, error in
            completionBlock(error)
        }
    }

    @nonobjc
    public func removeUserProfileImage(forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let urlString = "\(account.server)/ocs/v2.php/apps/spreed/temp-user-avatar"

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    internal func getProfileImagePath(forAccount account: TalkAccount, withStyle style: UIUserInterfaceStyle) -> String? {
        let fileManager = FileManager.default

        guard let documentsPath = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?.path,
              let accountHost = URL(string: account.server)?.host()
        else { return nil }

        let fileName: String

        if style == .dark {
            fileName = "\(account.userId)-\(accountHost)-dark.png"
        } else {
            fileName = "\(account.userId)-\(accountHost).png"
        }

        return (documentsPath as NSString).appendingPathComponent(fileName)
    }

    public func saveProfileImage(forAccount account: TalkAccount) {
        self.getAndStoreProfileImage(forAccount: account, withStyle: .light)
    }

    public func getAndStoreProfileImage(forAccount account: TalkAccount, withStyle style: UIUserInterfaceStyle) {
        var operation: SDWebImageCombinedOperation?

        // When getting our own profile image, we need to ignore any cache to always get the latest version
        operation = self.getUserAvatar(forUser: account.userId, withStyle: style, ignoreCache: true, forAccount: account, completionBlock: { image, _ in
            guard let token = operation?.loaderOperation as? SDWebImageDownloadToken,
                  let response = token.response as? HTTPURLResponse,
                  let image
            else { return }

            var hasCustomAvatar = false

            try? RLMRealm.default().transaction {
                let query = NSPredicate(format: "accountId = %@", account.accountId)
                if let customHeader = response.value(forHTTPHeaderField: "X-NC-IsCustomAvatar"),
                   let managedAccount = TalkAccount.objects(with: query).firstObject() as? TalkAccount {

                    hasCustomAvatar = (customHeader == "1")
                    managedAccount.hasCustomAvatar = hasCustomAvatar
                }
            }

            if let pngData = image.pngData(), let filePath = self.getProfileImagePath(forAccount: account, withStyle: style) {
                try? (pngData as NSData).write(toFile: filePath)
            }

            if let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId) {
                // If supported, try to fetch the dark version of the avatar as well
                if style == .light, !hasCustomAvatar, serverCapabilities.versionMajor >= 25 {
                    self.getAndStoreProfileImage(forAccount: account, withStyle: .dark)
                }
            }

            NotificationCenter.default.post(name: .NCUserProfileImageUpdated, object: self)
        })
    }

    public func userProfileImage(forAccount account: TalkAccount, withStyle style: UIUserInterfaceStyle) -> UIImage? {
        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        else { return nil }

        if style == .dark, !account.hasCustomAvatar && serverCapabilities.versionMajor >= 25 {
            if let filePath = self.getProfileImagePath(forAccount: account, withStyle: .dark) {
                return UIImage(contentsOfFile: filePath)
            }
        } else {
            if let filePath = self.getProfileImagePath(forAccount: account, withStyle: .light) {
                return UIImage(contentsOfFile: filePath)
            }
        }

        return nil
    }

    public func removeProfileImage(forAccount account: TalkAccount) {
        let fileManager = FileManager.default

        if let filePathLight = self.getProfileImagePath(forAccount: account, withStyle: .light) {
            try? fileManager.removeItem(atPath: filePathLight)
        }

        if let filePathDark = self.getProfileImagePath(forAccount: account, withStyle: .dark) {
            try? fileManager.removeItem(atPath: filePathDark)
        }
    }

    // MARK: - User avatar

    @nonobjc
    public func getUserAvatar(forUser userId: String, withStyle style: UIUserInterfaceStyle, forAccount account: TalkAccount, completionBlock: @escaping (_ image: UIImage?, _ error: Error?) -> Void) -> SDWebImageCombinedOperation? {
        return self.getUserAvatar(forUser: userId, withStyle: style, ignoreCache: false, forAccount: account, completionBlock: completionBlock)
    }

    @nonobjc
    public func getUserAvatar(forUser userId: String, withStyle style: UIUserInterfaceStyle, ignoreCache: Bool, forAccount account: TalkAccount, completionBlock: @escaping (_ image: UIImage?, _ error: Error?) -> Void) -> SDWebImageCombinedOperation? {
        guard let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let requestModifier = self.getRequestModifier(forAccount: account)
        else { return nil }

        // Since https://github.com/nextcloud/server/pull/31010 we can only request avatars in 64px or 512px
        // As we never request lower than 96px, we always get 512px anyway
        let avatarSize = 512

        var urlString = "\(account.server)/index.php/avatar/\(encodedUserId)/\(avatarSize)"

        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: account.accountId)
        if style == .dark, let serverCapabilities, serverCapabilities.versionMajor >= 25 {
            urlString = "\(urlString)/dark"
        }

        guard let url = URL(string: urlString) else { return nil }

        var options: SDWebImageOptions

        if ignoreCache {
            // In case we want to ignore our local caches, we can't provide SDWebImageRefreshCached, as this will
            // always use NSURLCache and could still return a cached value here
            options = [.retryFailed, .fromLoaderOnly]
        } else {
            // We want to refresh our cache when the NSURLCache determines that the resource is not fresh anymore
            // see: https://github.com/SDWebImage/SDWebImage/wiki/Common-Problems#handle-image-refresh
            // Could be removed when all conversations have a avatarVersion, see https://github.com/nextcloud/spreed/issues/9320
            options = [.retryFailed, .refreshCached]
        }

        return SDWebImageManager.shared.loadImage(with: url, options: options, context: [.downloadRequestModifier: requestModifier], progress: nil) { image, _, error, _, _, _ in
            if let error {
                // When the request was cancelled before completing, we expect no completion handler to be called
                if (error as NSError).code != SDWebImageError.cancelled.rawValue {
                    completionBlock(nil, error)
                }
            } else if let image {
                completionBlock(image, nil)
            }
        }
    }

    @nonobjc
    public func getFederatedUserAvatar(forUser userId: String, inRoom token: String?, withStyle style: UIUserInterfaceStyle, forAccount account: TalkAccount, completionBlock: @escaping (_ image: UIImage?, _ error: Error?) -> Void) -> SDWebImageCombinedOperation? {
        guard let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let requestModifier = self.getRequestModifier(forAccount: account)
        else { return nil }

        var encodedToken = "new"

        if let token, let tempEncodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            encodedToken = tempEncodedToken
        }

        var endpoint = "proxy/\(encodedToken)/user-avatar/512"

        if style == .dark {
            endpoint = "\(endpoint)/dark"
        }

        endpoint = "\(endpoint)?cloudId=\(encodedUserId)"

        let urlString = self.getRequestURL(forEndpoint: endpoint, withAPIType: .avatar, forAccount: account)
        let url = URL(string: urlString)

        guard let url else { return nil }

        // See getAvatarForRoom for explanation
        let options: SDWebImageOptions = [.retryFailed, .refreshCached, .queryDiskDataSync]

        // Make sure we get at least a 120x120 image when retrieving an SVG with SVGKit
        let context: [SDWebImageContextOption: Any] = [
            .downloadRequestModifier: requestModifier,
            .imageThumbnailPixelSize: CGSize(width: 120, height: 120)
        ]

        return SDWebImageManager.shared.loadImage(with: url, options: options, context: context, progress: nil) { image, _, error, _, _, _ in
            if let error {
                // When the request was cancelled before completing, we expect no completion handler to be called
                if (error as NSError).code != SDWebImageError.cancelled.rawValue {
                    completionBlock(nil, error)
                }
            } else if let image {
                completionBlock(image, nil)
            }
        }
    }

    // MARK: - Conversation avatars

    public func getAvatar(forRoom room: NCRoom, withStyle style: UIUserInterfaceStyle, completionBlock: @escaping (_ image: UIImage?, _ error: Error?) -> Void) -> SDWebImageCombinedOperation? {
        guard let encodedToken = room.token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: room.accountId),
              let requestModifier = self.getRequestModifier(forAccount: account)
        else { return nil }

        var endpoint = "room/\(encodedToken)/avatar"

        if style == .dark {
            endpoint = "\(endpoint)/dark"
        }

        // For non-one-to-one conversation we do have a valid avatarVersion which we can use to cache the avatar
        // For one-to-one conversations we rely on the caching that is specified by the server via cache-control header
        if room.type != .oneToOne {
            endpoint = "\(endpoint)?avatarVersion=\(room.avatarVersion ?? "")"
        }

        let urlString = self.getRequestURL(forEndpoint: endpoint, withAPIType: .avatar, forAccount: account)
        let url = URL(string: urlString)

        guard let url else { return nil }

        /*
         SDWebImageRetryFailed:         By default SDWebImage blacklists URLs that failed to load and does not try to
                                        load these URLs again, but we want to retry these.
                                        Also see https://github.com/SDWebImage/SDWebImage/wiki/Common-Problems#handle-image-refresh

         SDWebImageRefreshCached:       By default the cache-control header returned by the webserver is ignored and
                                        images are cached forever. With this parameter we let NSURLCache determine
                                        if a resource needs to be reloaded from the server again.
                                        Could be removed if this endpoint returns an avatar version for all calls.
                                        Also see https://github.com/nextcloud/spreed/issues/9320

         SDWebImageQueryDiskDataSync:   SDImage loads data from the disk cache on a separate (async) queue. This leads
                                        to 2 problems: 1. It can cause some flickering on a reload, 2. It causes UIImage methods
                                        being called to leak memory. This is noticeable in NSE with a tight memory constraint.
                                        SVG images rendered to UIImage with SVGKit will leak data and make NSE crash.
         */

        var options: SDWebImageOptions = [.retryFailed, .queryDiskDataSync]

        // Since we do not have a valid avatarVersion for one-to-one conversations, we need to rely on the
        // cache-control header by the server and therefore on NSURLCache
        // Note: There seems to be an issue with NSURLCache to correctly cache URLs that contain a query parameter
        // so it's currently only suiteable for one-to-ones that don't have a correct avatarVersion anyway
        if room.type == .oneToOne {
            options = [.retryFailed, .queryDiskDataSync, .refreshCached]
        }

        // Make sure we get at least a 120x120 image when retrieving an SVG with SVGKit
        let context: [SDWebImageContextOption: Any] = [
            .downloadRequestModifier: requestModifier,
            .imageThumbnailPixelSize: CGSize(width: 120, height: 120)
        ]

        return SDWebImageManager.shared.loadImage(with: url, options: options, context: context, progress: nil) { image, _, error, _, _, _ in
            if let error {
                // When the request was cancelled before completing, we expect no completion handler to be called
                if (error as NSError).code != SDWebImageError.cancelled.rawValue {
                    completionBlock(nil, error)
                }
            } else if let image {
                completionBlock(image, nil)
            }
        }
    }

    @nonobjc
    public func setAvatar(forRoom token: String, withImage image: UIImage, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId),
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let imageData = image.jpegData(compressionQuality: 0.7)
        else { return }

        let endpoint = "room/\(encodedToken)/avatar"
        let urlString = self.getRequestURL(forEndpoint: endpoint, withAPIType: .avatar, forAccount: account)

        apiSessionManager.post(urlString, parameters: nil) { formData in
            formData.appendPart(withFileData: imageData, name: "file", fileName: "avatar.jpg", mimeType: "image/jpeg")
        } progress: { _ in
        } success: { _, _ in
            completionBlock(nil)
        } failure: { _, error in
            completionBlock(error)
        }
    }

    @nonobjc
    public func setEmojiAvatar(forRoom token: String, withEmoji emoji: String, withColor color: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let endpoint = "room/\(encodedToken)/avatar/emoji"
        let urlString = self.getRequestURL(forEndpoint: endpoint, withAPIType: .avatar, forAccount: account)

        var parameters = [
            "emoji": emoji
        ]

        let rawColor = color.replacingOccurrences(of: "#", with: "")

        if !rawColor.isEmpty {
            parameters["color"] = rawColor
        }

        apiSessionManager.postOcs(urlString, account: account, parameters: parameters) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    @nonobjc
    public func removeAvatar(forRoom room: NCRoom, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let encodedToken = room.token.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let account = NCDatabaseManager.sharedInstance().talkAccount(forAccountId: room.accountId),
              let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { return }

        let endpoint = "room/\(encodedToken)/avatar"
        let urlString = self.getRequestURL(forEndpoint: endpoint, withAPIType: .avatar, forAccount: account)

        apiSessionManager.deleteOcs(urlString, account: account) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    // MARK: - File previews

    @nonobjc
    public func getPreviewForFile(_ fileId: String, width: Int, height: Int, forAccount account: TalkAccount, completionBlock: @escaping (_ image: UIImage?, _ error: Error?) -> Void) -> SDWebImageCombinedOperation? {
        var urlString: String

        if width > 0 {
            urlString = "\(account.server)/index.php/core/preview?fileId=\(fileId)&x=\(width)&y=\(height)&forceIcon=1"
        } else {
            urlString = "\(account.server)/index.php/core/preview?fileId=\(fileId)&x=-1&y=\(height)&a=1&forceIcon=1"
        }

        let url = URL(string: urlString)
        guard let url,
              let requestModifier = self.getRequestModifier(forAccount: account)
        else { return nil }

        let options: SDWebImageOptions = [.retryFailed, .refreshCached]

        let context: [SDWebImageContextOption: Any] = [
            .downloadRequestModifier: requestModifier
        ]

        return SDWebImageManager.shared.loadImage(with: url, options: options, context: context, progress: nil) { image, _, error, _, _, _ in
            if let error {
                // When the request was cancelled before completing, we expect no completion handler to be called
                if (error as NSError).code != SDWebImageError.cancelled.rawValue {
                    completionBlock(nil, error)
                }
            } else if let image {
                completionBlock(image, nil)
            }
        }
    }

    // MARK: - User status

    public func getUserStatus(forAccount account: TalkAccount, completionBlock: @escaping (_ userStatus: NCUserStatus?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/user_status/api/v1/user_status"

        apiSessionManager.getOcs(urlString, account: account) { ocsResponse, _ in
            completionBlock(NCUserStatus(dictionary: ocsResponse?.dataDict))
        }
    }

    @nonobjc
    public func setUserStatus(_ status: String, forAccount account: TalkAccount, completionBlock: @escaping (_ error: Error?) -> Void) {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else {
            completionBlock(nil)
            return
        }

        let urlString = "\(account.server)/ocs/v2.php/apps/user_status/api/v1/user_status/status"

        apiSessionManager.putOcs(urlString, account: account, parameters: ["statusType": status]) { _, ocsError in
            completionBlock(ocsError)
        }
    }

    // MARK: - NKCommon Delegate

    public func authenticationChallenge(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // The pinning check
        if CCCertificate.sharedManager().checkTrustedChallenge(challenge) {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

}
