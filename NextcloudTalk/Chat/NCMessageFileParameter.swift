//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers
public class NCMessageFileParameter: NCMessageParameter {

    public var path: String?
    public var mimetype: String?
    public var size: Int?
    public var previewAvailable: Bool = false
    public var fileStatus: NCChatFileStatus?
    public var previewImageHeight: Int = 0
    public var previewImageWidth: Int = 0
    public var width: Int = 0
    public var height: Int = 0
    public var blurhash: String?

    override init?(dictionary dict: [String: Any]?) {
        super.init(dictionary: dict)

        self.path = dict?["path"] as? String
        self.mimetype = dict?["mimetype"] as? String
        self.previewAvailable = (dict?["preview-available"] as? String == "yes")

        self.size = dict?[intForKey: "size"] ?? 0
        self.previewImageHeight = dict?[intForKey: "preview-image-height"] ?? 0
        self.previewImageWidth = dict?[intForKey: "preview-image-width"] ?? 0
        self.width = dict?[intForKey: "width"] ?? 0
        self.height = dict?[intForKey: "height"] ?? 0

        self.blurhash = dict?["blurhash"] as? String

        if let fileId = dict?["fileId"] as? String, let fileName = dict?["fileName"] as? String,
           let filePath = dict?["filePath"] as? String, let fileLocalPath = dict?["fileLocalPath"] as? String {

            self.fileStatus = NCChatFileStatus(fileId: fileId, fileName: fileName, filePath: filePath, fileLocalPath: fileLocalPath)
        }
    }

}
