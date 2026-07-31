//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit
import SDWebImage

extension NCAPIController {

    struct GiphyResult {
        let gifs: [GiphyGif]
        let cursor: Int
    }

    /// GIFs get their own image cache instead of using the shared one: they are much larger than
    /// avatars and file previews, and would evict those from the shared cache while browsing.
    static let giphyImageCache: SDImageCache = {
        let cache = SDImageCache(namespace: "giphy")
        cache.config.shouldDisableiCloud = true
        cache.config.maxDiskSize = 32 * 1024 * 1024

        // We expire the cache once on app launch, see AppDelegate
        cache.config.shouldRemoveExpiredDataWhenTerminate = false
        cache.config.shouldRemoveExpiredDataWhenEnterBackground = false

        return cache
    }()

    /// Context for loading the proxied GIFs of the Giphy integration.
    ///
    /// Measuring a GIF and displaying it later must use the same context to share cache entries –
    /// including `animatedImageClass`, as one cached as a still image would display without animating.
    func giphyImageContext(forAccount account: TalkAccount) -> [SDWebImageContextOption: Any]? {
        guard let requestModifier = self.getRequestModifier(forAccount: account) else { return nil }

        return [
            .downloadRequestModifier: requestModifier,
            .imageCache: Self.giphyImageCache,
            .animatedImageClass: SDAnimatedImage.self
        ]
    }

    /// Same as `giphyImageContext(forAccount:)`, but for the reference views in chat, which have no
    /// account at hand. The proxied URLs load without authentication, as they always have.
    var giphyReferenceImageContext: [SDWebImageContextOption: Any] {
        return [
            .imageCache: Self.giphyImageCache,
            .animatedImageClass: SDAnimatedImage.self
        ]
    }

    /// Loads a GIF that is proxied by the Nextcloud server, as returned in `thumbnailUrl`. The result
    /// is cached, so the cell displaying it afterwards gets it from the cache. User agent, certificate
    /// handling and a limit of 6 parallel downloads come from the shared `SDWebImageDownloader`.
    func getGiphyGifImage(forAccount account: TalkAccount, url: URL) async throws -> UIImage {
        guard let context = self.giphyImageContext(forAccount: account)
        else { throw ApiControllerError.preconditionError }

        return try await withCheckedThrowingContinuation { continuation in
            // The operation is not kept to cancel it: a completed download ends up in the cache, so
            // it is not wasted even when its search is no longer current
            _ = SDWebImageManager.shared.loadImage(with: url, options: [], context: context, progress: nil) { image, _, error, _, _, _ in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? ApiControllerError.unexpectedOcsResponse)
                }
            }
        }
    }

    func getGiphyTrending(forAccount account: TalkAccount, cursor: Int, limit: Int) async throws -> GiphyResult {
        return try await self.getGiphyGifs(forAccount: account, endpoint: "gifs/trending", parameters: ["cursor": cursor, "limit": limit])
    }

    func searchGiphy(forAccount account: TalkAccount, term: String, cursor: Int, limit: Int) async throws -> GiphyResult {
        return try await self.getGiphyGifs(forAccount: account, endpoint: "gifs/search", parameters: ["term": term, "cursor": cursor, "limit": limit])
    }

    private func getGiphyGifs(forAccount account: TalkAccount, endpoint: String, parameters: [String: Any]) async throws -> GiphyResult {
        guard let apiSessionManager = self.getAPISessionManager(forAccountId: account.accountId)
        else { throw ApiControllerError.preconditionError }

        let urlString = "\(account.server)/ocs/v2.php/apps/integration_giphy/api/v1/\(endpoint)"

        // integration_giphy can return 401 when not configured, which would log out the account.
        // While we check that beforehand we opt-out of the checking the response to be on the safe side.
        let response = try await apiSessionManager.getOcs(urlString, account: account, parameters: parameters, checkResponseStatusCode: false)

        guard let dataDict = response.dataDict,
              let entries = dataDict["entries"] as? [[String: Any]]
        else { throw ApiControllerError.unexpectedOcsResponse }

        let gifs = entries.compactMap { GiphyGif(dictionary: $0) }
        let cursor = dataDict["cursor"] as? Int ?? 0

        return GiphyResult(gifs: gifs, cursor: cursor)
    }
}
