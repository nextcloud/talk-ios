//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import NextcloudKit

struct RoomInfoFileSection: View {
    let hostingWrapper: HostingControllerWrapper

    @Binding var room: NCRoom

    // QuickLook needs to be set on the List in RoomInfoSwiftUIView, if set here, it closes directly on the first show
    @Binding var quickLookUrl: URL?

    @State private var isDownloadingPreview: Bool = false
    @State private var isFetchingFileId: Bool = false

    private let openInText = String(format: NSLocalizedString("Open in %@", comment: ""), filesAppName)

    var body: (some View)? {
        guard room.objectType == NCRoomObjectTypeFile else {
            return Body.none
        }

        return Section(header: Text("Linked file")) {
            Button(action: previewFile) {
                HStack {
                    ImageSublabelView(image: Image(systemName: "eye").renderingMode(.template)) {
                        HStack {
                            Text("Preview")

                            if isDownloadingPreview {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                }
            }
            .foregroundStyle(.primary)
            .disabled(isDownloadingPreview)

            Button(action: openFileInFilesApp) {
                ImageSublabelView(image: Image("logo-action").renderingMode(.template)) {
                    HStack {
                        Text(verbatim: openInText)

                        if isFetchingFileId {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            }
            .foregroundStyle(.primary)
            .disabled(isFetchingFileId)
        }
    }

    func previewFile() {
        self.isDownloadingPreview = true

        NCChatFileControllerWrapper.shared.downloadFile(withFileId: room.objectId) { @MainActor fileLocalPath in
            self.isDownloadingPreview = false

            guard let fileLocalPath else { return }

            self.quickLookUrl = URL(fileURLWithPath: fileLocalPath)
        }
    }

    func openFileInFilesApp() {
        self.isFetchingFileId = true

        NCAPIController.sharedInstance().getFileById(forAccount: room.account!, withFileId: room.objectId) { file, _ in
            self.isFetchingFileId = false

            guard let account = room.account, let objectId = room.objectId else { return }

            if let file {
                let remoteDavPrefix = String(format: "/remote.php/dav/files/%@/", account.userId)
                let directoryPath = file.path.components(separatedBy: remoteDavPrefix).last!

                let filePath = "\(directoryPath)\(file.fileName)"
                let fileLink = "\(account.server)/index.php/f/\(objectId)"

                NCUtils.openFileInNextcloudAppOrBrowser(path: filePath, withFileLink: fileLink)

                return
            }

            NCUserInterfaceController.sharedInstance().presentAlert(withTitle: NSLocalizedString("Unable to open file", comment: ""),
                                                                    withMessage: String(format: NSLocalizedString("An error occurred while opening the file %@", comment: ""), room.name))
        }
    }
}
