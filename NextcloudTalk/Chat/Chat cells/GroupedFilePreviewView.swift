//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

protocol GroupedFilePreviewViewDelegate: AnyObject {
    /// The file at this position of the group was tapped, counted in the order the files were shared in.
    func groupedFilePreviewView(_ view: GroupedFilePreviewView, didSelectFileAt index: Int)
}

/// The files of one upload, shown as a row of previews.
///
/// Media with a preview becomes a row of square tiles, everything else a list of rows underneath,
/// which is the layout the web client settled on. Only a few tiles fit a chat bubble, so the last
/// one carries a "+N" badge for the media that does not fit.
class GroupedFilePreviewView: UIView {

    /// Tiles shown before the last one becomes the "+N" badge, when the bubble is wide enough
    static let maximumTiles = 4

    static let tileSize = 80.0

    /// Tall enough for the two lines a file row shows, so that it follows the text size the reader
    /// has chosen instead of clipping at a fixed height
    static var fileRowHeight: CGFloat {
        let nameHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let detailHeight = UIFont.preferredFont(forTextStyle: .footnote).lineHeight

        return ceil(nameHeight + detailHeight) + 2 * GroupedFileRowView.cardPadding
    }

    /// Between the tiles, between the cards, and between the two rows, so that a group is spaced
    /// the same way wherever you look at it
    static let contentSpacing = 4.0

    /// How many tiles fit next to each other.
    ///
    /// The tiles keep their size and the row shows fewer of them, rather than the tiles shrinking
    /// to fit: the chat view measures a group before building it, and a tile of a fixed size is
    /// something both can agree on without knowing the exact width of a bubble.
    static func tileCount(forAvailableWidth availableWidth: CGFloat) -> Int {
        guard availableWidth > 0 else { return self.maximumTiles }

        let fitting = Int((availableWidth + self.contentSpacing) / (self.tileSize + self.contentSpacing))

        return max(2, min(self.maximumTiles, fitting))
    }

    weak var delegate: GroupedFilePreviewViewDelegate?

    private var tileViews: [GroupedFilePreviewTileView] = []
    private var fileRowViews: [GroupedFileRowView] = []

    private lazy var tileRow: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = GroupedFilePreviewView.contentSpacing
        stackView.alignment = .top
        return stackView
    }()

    private lazy var fileRows: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = GroupedFilePreviewView.contentSpacing
        stackView.alignment = .fill
        return stackView
    }()

    /// Takes the width the tiles do not need, so that the stack view stretches this instead of
    /// stretching the last tile when a file row is longer than the tile row
    private lazy var tileRowSpacer: UIView = {
        let view = UIView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }()

    private lazy var contentStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [self.tileRow, self.fileRows])
        stackView.axis = .vertical
        stackView.spacing = GroupedFilePreviewView.contentSpacing
        // The rows are as wide as the widest thing in the bubble, so that all of a row takes taps
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupContentView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupContentView()
    }

    private var contentWidthConstraint: NSLayoutConstraint?

    private func setupContentView() {
        self.addSubview(self.contentStackView)
        self.tileRow.addArrangedSubview(self.tileRowSpacer)

        // A cap, not a width: the group is otherwise as wide as the longest thing in it, so a
        // bubble of file rows ends at the longest name instead of running to the edge
        let contentWidthConstraint = self.widthAnchor.constraint(lessThanOrEqualToConstant: 0)
        self.contentWidthConstraint = contentWidthConstraint

        // The rows keep the height they need. When the cell turns out taller than the group, as a
        // hand written height calculation now and then will, the difference is left below them
        // rather than stretching a card to fill it.
        let bottomConstraint = self.contentStackView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        bottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            self.contentStackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.contentStackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.contentStackView.topAnchor.constraint(equalTo: self.topAnchor),
            self.contentStackView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor),
            bottomConstraint
        ])
    }

    // MARK: - Layout of a group

    /// How the files of a group are split between the two rows, which is all the height of the view
    /// depends on. Kept separate so that the chat view can measure a group without building it.
    struct Layout {
        let tiles: [NCMessageFileParameter]
        let files: [NCMessageFileParameter]

        /// The media that does not fit the row, shown as a badge on the last tile
        let hiddenTileCount: Int

        init(files: [NCMessageFileParameter], availableWidth: CGFloat) {
            let media = files.filter { $0.isPreviewableMedia }
            let others = files.filter { !$0.isPreviewableMedia }
            let fittingTiles = GroupedFilePreviewView.tileCount(forAvailableWidth: availableWidth)

            if media.count > fittingTiles {
                // The last tile becomes the badge, so it stands for itself and everything after it
                self.tiles = Array(media.prefix(fittingTiles))
                self.hiddenTileCount = media.count - (fittingTiles - 1)
            } else {
                self.tiles = media
                self.hiddenTileCount = 0
            }

            self.files = others
        }

        var height: CGFloat {
            var height = 0.0

            if !self.tiles.isEmpty {
                // The tiles are square
                height += GroupedFilePreviewView.tileSize
            }

            if !self.files.isEmpty {
                height += CGFloat(self.files.count) * GroupedFilePreviewView.fileRowHeight
                height += CGFloat(self.files.count - 1) * GroupedFilePreviewView.contentSpacing

                if !self.tiles.isEmpty {
                    height += GroupedFilePreviewView.contentSpacing
                }
            }

            return height
        }

        /// The widest the group may be drawn. Within it the group is as wide as its content.
        ///
        /// A full row of tiles caps it, so that a long file name truncates rather than stretching
        /// the bubble and leaving a gap beside the tiles that nothing could fill.
        ///
        /// A row with room for another tile does not: the gap next to it is one the tiles could
        /// have used, and holding the file names down to a couple of tiles' width costs more than
        /// the gap does. Groups without any tiles have nothing to go by and may use the full width.
        func maximumContentWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
            let fittingTiles = GroupedFilePreviewView.tileCount(forAvailableWidth: availableWidth)

            guard !self.tiles.isEmpty, self.tiles.count >= fittingTiles else { return availableWidth }

            let tileCount = CGFloat(self.tiles.count)
            let tileRowWidth = tileCount * GroupedFilePreviewView.tileSize + (tileCount - 1) * GroupedFilePreviewView.contentSpacing

            return min(availableWidth, tileRowWidth)
        }
    }

    // MARK: - Content

    func setup(with group: FileMessageGroup, account: TalkAccount, availableWidth: CGFloat) {
        let files = group.messagesInUploadOrder.compactMap { $0.file() }
        let layout = Layout(files: files, availableWidth: availableWidth)

        let maximumContentWidth = layout.maximumContentWidth(forAvailableWidth: availableWidth)

        self.prepareForReuse()

        // Nothing may grow past this: a subview outside the bubble is not only clipped, it also
        // stops receiving taps
        self.contentWidthConstraint?.constant = maximumContentWidth
        self.contentWidthConstraint?.isActive = maximumContentWidth > 0

        for (index, file) in layout.tiles.enumerated() {
            let isBadge = layout.hiddenTileCount > 0 && index == layout.tiles.count - 1
            let tileView = GroupedFilePreviewTileView()

            tileView.setup(with: file, account: account, size: GroupedFilePreviewView.tileSize, hiddenCount: isBadge ? layout.hiddenTileCount : 0)
            tileView.addAction { [weak self] in
                guard let self else { return }

                self.delegate?.groupedFilePreviewView(self, didSelectFileAt: self.index(of: file, in: files))
            }

            self.tileViews.append(tileView)
            self.tileRow.insertArrangedSubview(tileView, at: index)
        }

        for file in layout.files {
            let rowView = GroupedFileRowView()

            rowView.setup(with: file, maximumWidth: maximumContentWidth)
            rowView.addAction { [weak self] in
                guard let self else { return }

                self.delegate?.groupedFilePreviewView(self, didSelectFileAt: self.index(of: file, in: files))
            }

            self.fileRowViews.append(rowView)
            self.fileRows.addArrangedSubview(rowView)
        }

        self.tileRow.isHidden = layout.tiles.isEmpty
        self.fileRows.isHidden = layout.files.isEmpty
    }

    /// Passes a download notification on to the row it belongs to, if any of them.
    func updateDownloadStatus(from notification: Notification) {
        for rowView in self.fileRowViews {
            rowView.updateDownloadStatus(from: notification)
        }
    }

    private func index(of file: NCMessageFileParameter, in files: [NCMessageFileParameter]) -> Int {
        return files.firstIndex { $0.parameterId == file.parameterId } ?? 0
    }

    func prepareForReuse() {
        for tileView in self.tileViews {
            tileView.prepareForReuse()
            self.tileRow.removeArrangedSubview(tileView)
            tileView.removeFromSuperview()
        }

        for rowView in self.fileRowViews {
            self.fileRows.removeArrangedSubview(rowView)
            rowView.removeFromSuperview()
        }

        self.tileViews = []
        self.fileRowViews = []
    }
}
