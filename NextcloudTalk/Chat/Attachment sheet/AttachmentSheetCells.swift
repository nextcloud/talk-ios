//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import Photos
import UIKit

/// A photo or a video of the grid, with a circle that shows its place in the selection
final class AttachmentAssetCell: UICollectionViewCell {

    static let reuseIdentifier = "AttachmentAssetCell"

    private static let circleSize: CGFloat = 26

    /// Which asset the cell shows, to ignore thumbnails that arrive after the cell was reused
    var representedAssetIdentifier: String?
    var imageRequestID = PHInvalidImageRequestID

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemFill
        imageView.isAccessibilityElement = false
        return imageView
    }()

    private let dimView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        view.isHidden = true
        return view
    }()

    private let durationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.7
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        return label
    }()

    private let circleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AttachmentAssetCell.circleSize / 2
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.white.cgColor
        view.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        return view
    }()

    private let numberLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: UIFont.systemFont(ofSize: 12, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.textAlignment = .center
        label.textColor = .white
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.contentView.addSubview(self.imageView)
        self.contentView.addSubview(self.dimView)
        self.contentView.addSubview(self.durationLabel)
        self.contentView.addSubview(self.circleView)
        self.circleView.addSubview(self.numberLabel)

        NSLayoutConstraint.activate([
            self.imageView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.imageView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            self.imageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.imageView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),

            self.dimView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.dimView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            self.dimView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.dimView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),

            self.durationLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 6),
            self.durationLabel.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -4),
            self.durationLabel.trailingAnchor.constraint(lessThanOrEqualTo: self.contentView.trailingAnchor, constant: -6),

            self.circleView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 6),
            self.circleView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -6),
            self.circleView.widthAnchor.constraint(equalToConstant: Self.circleSize),
            self.circleView.heightAnchor.constraint(equalToConstant: Self.circleSize),

            self.numberLabel.leadingAnchor.constraint(equalTo: self.circleView.leadingAnchor, constant: 2),
            self.numberLabel.trailingAnchor.constraint(equalTo: self.circleView.trailingAnchor, constant: -2),
            self.numberLabel.centerYAnchor.constraint(equalTo: self.circleView.centerYAnchor)
        ])

        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.representedAssetIdentifier = nil
        self.imageRequestID = PHInvalidImageRequestID
        self.imageView.image = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // CGColors do not follow the appearance on their own
        self.circleView.layer.borderColor = self.selectionIndex == nil ? UIColor.white.cgColor : UIColor.tintColor.cgColor
    }

    private(set) var selectionIndex: Int?

    func setThumbnail(_ image: UIImage?) {
        self.imageView.image = image
    }

    func configure(for asset: PHAsset) {
        let isVideo = asset.mediaType == .video

        self.durationLabel.text = isVideo ? InAppCameraSupport.formattedDuration(asset.duration) : nil
        self.durationLabel.isHidden = !isVideo

        let kind = isVideo ? NSLocalizedString("Video", comment: "A video in the photo library") : NSLocalizedString("Photo", comment: "A photo in the photo library")

        if let date = asset.creationDate {
            self.accessibilityLabel = "\(kind), \(Self.dateFormatter.string(from: date))"
        } else {
            self.accessibilityLabel = kind
        }

        if isVideo {
            self.accessibilityLabel = "\(self.accessibilityLabel ?? kind), \(InAppCameraSupport.formattedDuration(asset.duration))"
        }
    }

    /// - Parameter index: The place in the selection, starting at 1, or `nil` when the item is not selected
    func setSelectionIndex(_ index: Int?) {
        self.selectionIndex = index

        if let index {
            self.numberLabel.text = "\(index)"
            self.circleView.backgroundColor = .tintColor
            self.circleView.layer.borderColor = UIColor.tintColor.cgColor
            self.dimView.isHidden = false
            self.accessibilityValue = NSLocalizedString("Selected", comment: "An item of the attachment sheet is selected") + ", \(index)"
            self.accessibilityTraits = [.button, .selected]
        } else {
            self.numberLabel.text = nil
            self.circleView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
            self.circleView.layer.borderColor = UIColor.white.cgColor
            self.dimView.isHidden = true
            self.accessibilityValue = nil
            self.accessibilityTraits = .button
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

/// The first tile of the grid: a live view of the camera, or an icon when the camera can not be used right now
final class AttachmentCameraCell: UICollectionViewCell {

    static let reuseIdentifier = "AttachmentCameraCell"

    private let iconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "camera.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        return imageView
    }()

    private var previewView: VideoMessagePreviewView?
    private var previewSession: AVCaptureSession?
    private var previewOrientation: UIInterfaceOrientation?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.contentView.backgroundColor = .darkGray
        self.contentView.clipsToBounds = true
        self.contentView.addSubview(self.iconView)

        NSLayoutConstraint.activate([
            self.iconView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.iconView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor)
        ])

        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
        self.accessibilityLabel = NSLocalizedString("Camera", comment: "")
        self.accessibilityIdentifier = "attachmentSheetCameraTile"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameter session: The session to show, or `nil` to show only the icon
    func configure(session: AVCaptureSession?, interfaceOrientation: UIInterfaceOrientation) {
        if self.previewSession === session, self.previewOrientation == interfaceOrientation {
            return
        }

        self.previewView?.removeFromSuperview()
        self.previewView = nil
        self.previewSession = session
        self.previewOrientation = interfaceOrientation

        guard let session else { return }

        let previewView = VideoMessagePreviewView(session: session, interfaceOrientation: interfaceOrientation, showsSwitchCameraButton: false)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.layer.cornerRadius = 0
        previewView.isUserInteractionEnabled = false
        previewView.isAccessibilityElement = false

        // Below the icon, so the tile is recognizable as the camera
        self.contentView.insertSubview(previewView, belowSubview: self.iconView)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor)
        ])

        self.previewView = previewView
    }
}
