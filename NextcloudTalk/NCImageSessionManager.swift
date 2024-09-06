//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class NCImageSessionManager: NCBaseSessionManager {

    public static let shared = NCImageSessionManager()

    public var cache: URLCache

    init() {
        let configuration = AFImageDownloader.defaultURLSessionConfiguration()

        // Try to remove legacy ImageCache directory in app group
        if let legacyCacheURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?.appendingPathComponent("ImageCache") {
            try? FileManager.default .removeItem(at: legacyCacheURL)
        }

        // In case of images we want to use the cache and store it on disk
        // As we use the memory cache from AFImageDownloader, we only want disk cache here
        let imageCacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("ImageCache")
        self.cache = URLCache(memoryCapacity: 0, diskCapacity: 100 * 1024 * 1024, directory: imageCacheURL)

        configuration.urlCache = self.cache

        super.init(configuration: configuration, responseSerializer: AFImageResponseSerializer(), requestSerializer: AFHTTPRequestSerializer())

        var acceptableTypes = self.responseSerializer.acceptableContentTypes
        acceptableTypes?.insert("image/jpg")
        self.responseSerializer.acceptableContentTypes = acceptableTypes
    }

}
