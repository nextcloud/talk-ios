//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Ivan Sein <ivan@nextcloud.com>
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

@objcMembers public class NCImageSessionManager: NCBaseSessionManager {

    public static let shared = NCImageSessionManager()

    public var cache: URLCache

    init() {
        let configuration = AFImageDownloader.defaultURLSessionConfiguration()

        // In case of images we want to use the cache and store it on disk
        // As we use the memory cache from AFImageDownloader, we only want disk cache here
        let imageCacheURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?.appendingPathComponent("ImageCache")
        self.cache = URLCache(memoryCapacity: 0, diskCapacity: 100 * 1024 * 1024, directory: imageCacheURL)

        configuration.urlCache = self.cache

        super.init(configuration: configuration, responseSerializer: AFImageResponseSerializer(), requestSerializer: AFHTTPRequestSerializer())

        var acceptableTypes = self.responseSerializer.acceptableContentTypes
        acceptableTypes?.insert("image/jpg")
        self.responseSerializer.acceptableContentTypes = acceptableTypes
    }

}
