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

@objcMembers public class NCPushProxySessionManager: NCBaseSessionManager {

    public static let shared = NCPushProxySessionManager()

    init() {
        let configuration = URLSessionConfiguration.default
        super.init(configuration: configuration, responseSerializer: AFHTTPResponseSerializer(), requestSerializer: AFHTTPRequestSerializer())

        self.userAgent += " (Strict VoIP)"
        self.updateUserAgent()

        // As we can run max. 30s in the background, we need to lower the default timeout from 60s to something < 30s.
        // Otherwise our app can be killed when trying to register while in the background
        self.requestSerializer.timeoutInterval = 25
    }

}
