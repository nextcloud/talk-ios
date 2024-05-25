//
// Copyright (c) 2024 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Marcel Müller <marcel.mueller@nextcloud.com>
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

@objcMembers public class NCChatFileStatus: NSObject {

    public var fileId: String
    public var fileName: String
    public var filePath: String
    public var fileLocalPath: String?
    public var isDownloading: Bool = false
    public var canReportProgress: Bool = false
    public var downloadProgress: Float = 0

    init(fileId: String, fileName: String, filePath: String) {
        self.fileId = fileId
        self.fileName = fileName
        self.filePath = filePath
    }

    public func isStatusFor(messageFileParameter parameter: NCMessageFileParameter) -> Bool {
        return self.fileId == parameter.parameterId && self.filePath == parameter.path
    }
}
