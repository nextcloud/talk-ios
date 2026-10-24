//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// Shows the upload state of a file that is still being shared in the background on top of its preview.
class FileUploadOverlayView: UIView {

    enum Style {
        /// Dims the whole preview, with the state in its center
        case covering
        /// Leaves the preview as it is, with a small state in its top right corner
        case corner
    }

    private let style: Style

    private lazy var uploadIndicator: MDCActivityIndicator = {
        let indicator = MDCActivityIndicator(frame: .init(x: 0, y: 0, width: self.indicatorSize, height: self.indicatorSize))
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.radius = self.style == .covering ? 10 : 7
        indicator.strokeWidth = self.style == .covering ? 2.5 : 2
        indicator.cycleColors = [.white]
        return indicator
    }()

    /// A clock while waiting for the retry, no network, or a checkmark once uploaded
    private lazy var stateImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private var indicatorSize: CGFloat {
        return self.style == .covering ? 28 : 20
    }

    init(style: Style = .covering) {
        self.style = style
        super.init(frame: .zero)
        self.setupOverlayView()
    }

    required init?(coder: NSCoder) {
        self.style = .covering
        super.init(coder: coder)
        self.setupOverlayView()
    }

    private func setupOverlayView() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.isUserInteractionEnabled = false
        self.isHidden = true

        self.addSubview(self.uploadIndicator)
        self.addSubview(self.stateImageView)

        let imageSize: CGFloat = self.style == .covering ? 24 : 16

        NSLayoutConstraint.activate([
            self.uploadIndicator.widthAnchor.constraint(equalToConstant: self.indicatorSize),
            self.uploadIndicator.heightAnchor.constraint(equalToConstant: self.indicatorSize),
            self.stateImageView.centerXAnchor.constraint(equalTo: self.uploadIndicator.centerXAnchor),
            self.stateImageView.centerYAnchor.constraint(equalTo: self.uploadIndicator.centerYAnchor),
            self.stateImageView.widthAnchor.constraint(equalToConstant: imageSize),
            self.stateImageView.heightAnchor.constraint(equalToConstant: imageSize)
        ])

        switch self.style {
        case .covering:
            self.backgroundColor = .black.withAlphaComponent(0.35)

            NSLayoutConstraint.activate([
                self.uploadIndicator.centerXAnchor.constraint(equalTo: self.centerXAnchor),
                self.uploadIndicator.centerYAnchor.constraint(equalTo: self.centerYAnchor)
            ])
        case .corner:
            NSLayoutConstraint.activate([
                self.uploadIndicator.topAnchor.constraint(equalTo: self.topAnchor, constant: 4),
                self.uploadIndicator.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -4)
            ])
        }
    }

    func pin(to view: UIView) {
        view.addSubview(self)

        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            self.topAnchor.constraint(equalTo: view.topAnchor),
            self.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func update(for message: NCChatMessage) {
        self.update(state: message.backgroundUploadState, progress: message.backgroundUploadProgress)
    }

    /// Hides for anything but a file that is still being shared in the background.
    func update(state: ChatBackgroundUploadState?, progress: Float) {
        guard let state, state != .failed else {
            // Fades out when the posted message replaced the pending one in place
            self.hide(animated: !self.isHidden)
            return
        }

        if let symbolName = state.symbolName {
            self.showImage(named: symbolName)
        } else {
            self.showUpload(withProgress: progress)
        }
    }

    /// Without a progress yet, the indicator spins.
    func showUpload(withProgress progress: Float) {
        self.prepareToShow()
        self.stateImageView.isHidden = true
        self.uploadIndicator.isHidden = false

        if progress > 0 {
            self.uploadIndicator.indicatorMode = .determinate
            self.uploadIndicator.setProgress(progress, animated: true)
        } else {
            self.uploadIndicator.indicatorMode = .indeterminate
        }

        self.uploadIndicator.startAnimating()
    }

    private func showImage(named systemName: String) {
        self.prepareToShow()
        self.uploadIndicator.stopAnimating()
        self.uploadIndicator.isHidden = true
        self.stateImageView.image = UIImage(systemName: systemName)
        self.stateImageView.isHidden = false
    }

    private func prepareToShow() {
        self.layer.removeAllAnimations()
        self.alpha = 1
        self.isHidden = false
    }

    /// Fades out when the file was posted while being shown, so its preview stays in place.
    func hide(animated: Bool = false) {
        guard animated, !self.isHidden else {
            self.layer.removeAllAnimations()
            self.isHidden = true
            self.alpha = 1
            self.uploadIndicator.stopAnimating()
            return
        }

        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0
        }, completion: { finished in
            guard finished else { return }

            self.isHidden = true
            self.alpha = 1
            self.uploadIndicator.stopAnimating()
        })
    }
}
