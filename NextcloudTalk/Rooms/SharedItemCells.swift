//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import MapKit
import SDWebImage

/// Shows the download progress of its file as accessory
class SharedItemTableViewCell: UITableViewCell {

    var fileParameter: NCMessageFileParameter?
    private var activityIndicator: NCActivityIndicator?

    let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        NotificationCenter.default.addObserver(self, selector: #selector(didChangeIsDownloading(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeIsDownloading, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeDownloadProgress(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeDownloadProgress, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.fileParameter = nil
        self.accessoryView = nil
        self.activityIndicator = nil
    }

    static func detailText(for message: NCChatMessage, includingActor: Bool) -> String {
        var parts: [String] = []

        if includingActor, let actorDisplayName = message.actorDisplayName, !actorDisplayName.isEmpty {
            parts.append(actorDisplayName)
        }

        parts.append(NCUtils.relativeTimeFromDate(date: Date(timeIntervalSince1970: Double(message.timestamp))))

        return parts.joined(separator: " ⸱ ")
    }

    @objc private func didChangeIsDownloading(notification: Notification) {
        DispatchQueue.main.async {
            guard let fileParameter = self.fileParameter,
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
            else { return }

            if receivedStatus.isDownloading, self.activityIndicator == nil {
                self.addActivityIndicator(with: 0)
            } else if !receivedStatus.isDownloading, self.activityIndicator != nil {
                self.accessoryView = nil
                self.activityIndicator = nil
            }
        }
    }

    @objc private func didChangeDownloadProgress(notification: Notification) {
        DispatchQueue.main.async {
            guard let fileParameter = self.fileParameter,
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
            else { return }

            if let activityIndicator = self.activityIndicator {
                if receivedStatus.canReportProgress {
                    activityIndicator.indicatorMode = .determinate
                    activityIndicator.setProgress(Float(receivedStatus.downloadProgress), animated: true)
                }
            } else {
                self.addActivityIndicator(with: Float(receivedStatus.downloadProgress))
            }
        }
    }

    private func addActivityIndicator(with progress: Float) {
        let indicator = NCActivityIndicator(frame: .init(x: 0, y: 0, width: 20, height: 20))
        self.activityIndicator = indicator

        indicator.radius = 7.0
        indicator.cycleColors = [.systemGray2]

        if progress > 0 {
            indicator.indicatorMode = .determinate
            indicator.setProgress(progress, animated: false)
        }

        indicator.startAnimating()
        self.accessoryView = indicator
    }
}

// MARK: - Files

class SharedFileCell: SharedItemTableViewCell {

    static let identifier = "SharedFileCell"

    private static let previewSize: CGFloat = 56

    private var previewRequest: SDWebImageCombinedOperation?

    private let previewImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8.0
        imageView.backgroundColor = .tertiarySystemFill
        return imageView
    }()

    private let fileIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let sizeLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        let labelStack = UIStackView(arrangedSubviews: [self.titleLabel, self.detailLabel, self.sizeLabel])
        labelStack.axis = .vertical
        labelStack.spacing = 2

        self.contentView.addSubview(self.previewImageView)
        self.previewImageView.addSubview(self.fileIconView)
        self.contentView.addSubview(labelStack)

        for view in [self.previewImageView, self.fileIconView, labelStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            self.previewImageView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor),
            self.previewImageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            self.previewImageView.widthAnchor.constraint(equalToConstant: Self.previewSize),
            self.previewImageView.heightAnchor.constraint(equalToConstant: Self.previewSize),
            self.previewImageView.topAnchor.constraint(greaterThanOrEqualTo: self.contentView.topAnchor, constant: 10),

            self.fileIconView.centerXAnchor.constraint(equalTo: self.previewImageView.centerXAnchor),
            self.fileIconView.centerYAnchor.constraint(equalTo: self.previewImageView.centerYAnchor),
            self.fileIconView.widthAnchor.constraint(equalToConstant: 36),
            self.fileIconView.heightAnchor.constraint(equalToConstant: 36),

            labelStack.leadingAnchor.constraint(equalTo: self.previewImageView.trailingAnchor, constant: 14),
            labelStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
            labelStack.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            labelStack.topAnchor.constraint(greaterThanOrEqualTo: self.contentView.topAnchor, constant: 10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.previewRequest?.cancel()
        self.previewRequest = nil
        self.previewImageView.image = nil
        self.fileIconView.image = nil
    }

    func configure(with message: NCChatMessage, showsServerPreview: Bool, account: TalkAccount) {
        guard let file = message.file() else { return }

        self.fileParameter = file
        self.titleLabel.text = file.name
        self.detailLabel.text = Self.detailText(for: message, includingActor: true)

        if let size = file.size, size > 0 {
            self.sizeLabel.text = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            self.sizeLabel.isHidden = false
        } else {
            self.sizeLabel.isHidden = true
        }

        self.fileIconView.image = UIImage(named: NCUtils.previewImage(forMimeType: file.mimetype))

        guard file.previewAvailable, showsServerPreview else { return }

        let fileId = file.parameterId
        let pixelSize = Int(Self.previewSize * 3)

        self.previewRequest = NCAPIController.sharedInstance().getPreviewForFile(fileId, width: pixelSize, height: pixelSize, forAccount: account) { [weak self] image, _ in
            guard let self, let image, self.fileParameter?.parameterId == fileId else { return }

            self.previewImageView.image = image
            self.fileIconView.image = nil
        }
    }
}

// MARK: - Voice messages and audio

protocol SharedAudioCellDelegate: AnyObject {
    func sharedAudioCellWantsToPlay(_ cell: SharedAudioCell)
    func sharedAudioCellWantsToPause(_ cell: SharedAudioCell)
    func sharedAudioCell(_ cell: SharedAudioCell, wantsToSeekTo time: TimeInterval)
}

class SharedAudioCell: SharedItemTableViewCell, AudioPlayerViewDelegate {

    static let identifier = "SharedAudioCell"

    weak var delegate: SharedAudioCellDelegate?
    private(set) var messageId: Int?

    let playerView = AudioPlayerView(frame: .init(x: 0, y: 0, width: 300, height: 52))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.selectionStyle = .none
        self.playerView.delegate = self
        self.playerView.resetPlayer()

        let labelStack = UIStackView(arrangedSubviews: [self.titleLabel, self.detailLabel])
        labelStack.axis = .vertical
        labelStack.spacing = 2

        self.contentView.addSubview(labelStack)
        self.contentView.addSubview(self.playerView)

        labelStack.translatesAutoresizingMaskIntoConstraints = false
        self.playerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            labelStack.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 12),
            labelStack.leadingAnchor.constraint(equalTo: self.playerView.leadingAnchor),
            labelStack.trailingAnchor.constraint(equalTo: self.playerView.trailingAnchor),

            self.playerView.topAnchor.constraint(equalTo: labelStack.bottomAnchor, constant: 8),
            self.playerView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 12),
            self.playerView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -12),
            self.playerView.heightAnchor.constraint(equalToConstant: 52),
            self.playerView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.messageId = nil
        self.playerView.resetPlayer()
    }

    /// Voice messages are titled by their sender, other audio files by their name
    func configure(with message: NCChatMessage) {
        let file = message.file()
        let actorDisplayName = message.actorDisplayName ?? ""

        self.messageId = message.messageId
        self.fileParameter = file

        if message.isVoiceMessage || file?.name.isEmpty != false {
            self.titleLabel.text = actorDisplayName
            self.detailLabel.text = Self.detailText(for: message, includingActor: false)
        } else {
            self.titleLabel.text = file?.name
            self.detailLabel.text = Self.detailText(for: message, includingActor: true)
        }
    }

    func audioPlayerPlayButtonPressed() {
        self.delegate?.sharedAudioCellWantsToPlay(self)
    }

    func audioPlayerPauseButtonPressed() {
        self.delegate?.sharedAudioCellWantsToPause(self)
    }

    func audioPlayerProgressChanged(progress: CGFloat) {
        self.delegate?.sharedAudioCell(self, wantsToSeekTo: TimeInterval(progress))
    }
}

// MARK: - Locations

class SharedLocationCell: SharedItemTableViewCell {

    static let identifier = "SharedLocationCell"

    private static let mapHeight: CGFloat = 140

    /// Rendering a snapshot takes a moment, so scrolling back shouldn't redo it
    private static let snapshotCache = NSCache<NSString, UIImage>()

    private var coordinate: CLLocationCoordinate2D?
    private var snapshotKey: String?
    private var snapshotter: MKMapSnapshotter?

    private let mapImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8.0
        imageView.backgroundColor = .tertiarySystemFill
        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.titleLabel.numberOfLines = 2

        let labelStack = UIStackView(arrangedSubviews: [self.titleLabel, self.detailLabel])
        labelStack.axis = .vertical
        labelStack.spacing = 2

        self.contentView.addSubview(self.mapImageView)
        self.contentView.addSubview(labelStack)

        self.mapImageView.translatesAutoresizingMaskIntoConstraints = false
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            self.mapImageView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 12),
            self.mapImageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 12),
            self.mapImageView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -12),
            self.mapImageView.heightAnchor.constraint(equalToConstant: Self.mapHeight),

            labelStack.topAnchor.constraint(equalTo: self.mapImageView.bottomAnchor, constant: 10),
            labelStack.leadingAnchor.constraint(equalTo: self.mapImageView.leadingAnchor),
            labelStack.trailingAnchor.constraint(equalTo: self.mapImageView.trailingAnchor),
            labelStack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.snapshotter?.cancel()
        self.snapshotter = nil
        self.snapshotKey = nil
        self.coordinate = nil
        self.mapImageView.image = nil
    }

    func configure(with message: NCChatMessage) {
        self.detailLabel.text = Self.detailText(for: message, includingActor: true)

        guard let geoLocationParameter = message.geoLocation() else { return }

        let geoLocation = GeoLocationRichObject(from: geoLocationParameter)
        self.titleLabel.text = geoLocation.name

        if let latitude = Double(geoLocation.latitude), let longitude = Double(geoLocation.longitude) {
            self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // The snapshot needs the final width, which is only known here
        self.updateSnapshotIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) ||
            self.traitCollection.displayScale != previousTraitCollection?.displayScale {
            self.updateSnapshotIfNeeded()
        }
    }

    private func updateSnapshotIfNeeded() {
        guard let coordinate = self.coordinate else { return }

        let size = self.mapImageView.bounds.size
        let scale = max(self.traitCollection.displayScale, 1)
        let style = self.traitCollection.userInterfaceStyle

        guard size.width > 0 else { return }

        let key = "\(coordinate.latitude),\(coordinate.longitude),\(Int(size.width))x\(Int(size.height))@\(scale),\(style.rawValue)"

        guard key != self.snapshotKey else { return }

        self.snapshotKey = key
        self.snapshotter?.cancel()

        if let cached = Self.snapshotCache.object(forKey: key as NSString) {
            self.mapImageView.image = cached
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005))
        options.size = size
        options.scale = scale
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)

        let snapshotter = MKMapSnapshotter(options: options)
        self.snapshotter = snapshotter

        snapshotter.start { [weak self] snapshot, _ in
            guard let snapshot else { return }

            let image = Self.image(of: snapshot, withPinAt: coordinate)
            Self.snapshotCache.setObject(image, forKey: key as NSString)

            guard let self, self.snapshotKey == key else { return }

            self.mapImageView.image = image
        }
    }

    private static func image(of snapshot: MKMapSnapshotter.Snapshot, withPinAt coordinate: CLLocationCoordinate2D) -> UIImage {
        let pin = MKPinAnnotationView(annotation: nil, reuseIdentifier: nil)
        pin.pinTintColor = NCAppBranding.elementColor()

        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale

        return UIGraphicsImageRenderer(size: snapshot.image.size, format: format).image { _ in
            snapshot.image.draw(at: .zero)

            var point = snapshot.point(for: coordinate)
            point.x += pin.centerOffset.x - (pin.bounds.width / 2)
            point.y += pin.centerOffset.y - (pin.bounds.height / 2)

            pin.image?.draw(at: point)
        }
    }
}
