//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

// Unobtrusive download progress shown on top of an already visible preview
@objcMembers class MediaDownloadIndicatorView: UIView {

    private static let preferredSize: CGFloat = 32

    private var retryHandler: (() -> Void)?
    private var backgroundView: UIVisualEffectView?

    private lazy var activityIndicator = {
        let activityIndicator = NCActivityIndicator(frame: .init(x: 0, y: 0, width: 24, height: 24))
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.radius = 9
        activityIndicator.strokeWidth = 2
        activityIndicator.indicatorMode = .indeterminate

        return activityIndicator
    }()

    private lazy var retryButton = {
        let retryButton = UIButton(type: .system)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        retryButton.isHidden = true
        retryButton.accessibilityLabel = NSLocalizedString("Retry", comment: "Retry downloading the original file")
        retryButton.addAction(UIAction { [weak self] _ in
            self?.retryHandler?()
        }, for: .touchUpInside)

        return retryButton
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.translatesAutoresizingMaskIntoConstraints = false

        self.addBackgroundView()

        // Foreground content belongs inside the effect view, that is what gets the legibility treatment
        let contentView = self.backgroundView?.contentView ?? self
        contentView.addSubview(self.activityIndicator)
        contentView.addSubview(self.retryButton)

        self.updateForegroundColor()
        self.observeGlassAppearance()

        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: MediaDownloadIndicatorView.preferredSize),
            self.heightAnchor.constraint(equalToConstant: MediaDownloadIndicatorView.preferredSize),
            self.activityIndicator.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.activityIndicator.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.retryButton.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.retryButton.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.retryButton.topAnchor.constraint(equalTo: self.topAnchor),
            self.retryButton.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.isAccessibilityElement = true
        self.accessibilityLabel = NSLocalizedString("Downloading full quality media", comment: "Accessibility label of the indicator shown while the original file is downloaded")
        self.accessibilityTraits = .updatesFrequently
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    ///
    /// Follows the appearance the glass picked for the brightness of the picture behind it.
    ///
    /// The glass reports that as a user interface style on its content view only, not on us. The
    /// indicator draws into a layer, whose color does not re-resolve on its own, so the color is
    /// resolved explicitly here.
    ///
    private func updateForegroundColor() {
        let contentTraitCollection = self.backgroundView?.contentView.traitCollection ?? self.traitCollection

        // Progress is ambient, the retry glyph is a control and stays at full strength
        self.activityIndicator.cycleColors = [UIColor.secondaryLabel.resolvedColor(with: contentTraitCollection)]
        self.retryButton.tintColor = UIColor.label.resolvedColor(with: contentTraitCollection)
    }

    private func observeGlassAppearance() {
        guard #available(iOS 17.0, *), let contentView = self.backgroundView?.contentView else { return }

        _ = contentView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: UIView, _: UITraitCollection) in
            self?.updateForegroundColor()
        }
    }

    private func addBackgroundView() {
        let backgroundView: UIVisualEffectView

        if #available(iOS 26.0, *) {
            backgroundView = self.addGlassView()
        } else {
            backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            self.insertSubview(backgroundView, at: 0)

            NSLayoutConstraint.activate([
                backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                backgroundView.topAnchor.constraint(equalTo: self.topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
            ])
        }

        // Glass draws outside its bounds, so it has to be clipped to the circle as well
        backgroundView.layer.cornerRadius = MediaDownloadIndicatorView.preferredSize / 2
        backgroundView.layer.masksToBounds = true

        self.backgroundView = backgroundView
    }

    func showProgress() {
        self.retryHandler = nil
        self.retryButton.isHidden = true
        self.activityIndicator.isHidden = false
        self.activityIndicator.startAnimating()

        self.isAccessibilityElement = true
    }

    func showRetry(handler: @escaping () -> Void) {
        self.retryHandler = handler
        self.activityIndicator.stopAnimating()
        self.activityIndicator.isHidden = true
        self.retryButton.isHidden = false

        // The button carries the accessibility information in this mode
        self.isAccessibilityElement = false
        self.accessibilityValue = nil
    }

    func stopAnimating() {
        self.activityIndicator.stopAnimating()
    }

    func setProgress(_ progress: Float) {
        guard self.retryHandler == nil else { return }

        self.activityIndicator.indicatorMode = .determinate
        self.activityIndicator.setProgress(progress, animated: true)
        self.accessibilityValue = String(format: "%.0f%%", progress * 100)
    }
}
