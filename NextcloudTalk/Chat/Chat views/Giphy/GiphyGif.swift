//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// A single GIF entry as returned by the integration_giphy OCS API.
///
/// The API returns `OCP\Search\SearchResultEntry` objects, which serialize to
/// `{ thumbnailUrl, title, subline, resourceUrl, icon, rounded, attributes }`.
struct GiphyGif: Sendable {

    /// Absolute URL to the proxied (fixed-width) GIF on the Nextcloud server. Used for the preview.
    let thumbnailUrl: URL

    /// Human readable title of the GIF.
    let title: String

    /// Additional information (e.g. the author's username).
    let subline: String

    /// The giphy.com link that is inserted into the chat when the GIF is selected.
    /// This is rendered as a Giphy reference by the chat (see ReferenceGiphyView).
    let resourceUrl: String

    init?(dictionary: [String: Any]) {
        guard let thumbnailUrlString = dictionary["thumbnailUrl"] as? String,
              let thumbnailUrl = URL(string: thumbnailUrlString),
              let resourceUrl = dictionary["resourceUrl"] as? String,
              !resourceUrl.isEmpty
        else { return nil }

        self.thumbnailUrl = thumbnailUrl
        self.resourceUrl = resourceUrl
        self.title = dictionary["title"] as? String ?? ""
        self.subline = dictionary["subline"] as? String ?? ""
    }
}
