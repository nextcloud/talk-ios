//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

class BarButtonItemWithActivity: UIBarButtonItem {

    var innerButton = UIButton()
    var activityIndicator = UIActivityIndicatorView()

    var textColor: UIColor {
        if #available(iOS 26.0, *) {
            return .label
        } else {
            return NCAppBranding.themeTextColor()
        }
    }

    init(image: UIImage) {
        super.init()

        var configuration = UIButton.Configuration.plain()
        configuration.image = image
        setupDefaultConfiguration(&configuration)

        self.innerButton.configuration = configuration

        self.activityIndicator.color = textColor
        self.activityIndicator.style = .medium

        self.innerButton.heightAnchor.constraint(equalToConstant: 36.0).isActive = true
        self.innerButton.widthAnchor.constraint(equalToConstant: 44.0).isActive = true

        self.activityIndicator.heightAnchor.constraint(equalToConstant: 36.0).isActive = true
        self.activityIndicator.widthAnchor.constraint(equalToConstant: 44.0).isActive = true

        self.innerButton.translatesAutoresizingMaskIntoConstraints = false

        self.customView = self.innerButton
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupDefaultConfiguration(_ config: inout UIButton.Configuration) {
        config.cornerStyle = .medium
        config.baseBackgroundColor = .clear
        config.baseForegroundColor = textColor

        // Apply 50% alpha to textColor when innerButton is disabled to override UIKit's automatic light/dark theme adjustments
        config.imageColorTransformer = UIConfigurationColorTransformer { [weak self] color in
            guard let self = self else { return color }
            if !self.innerButton.isEnabled {
                return self.textColor.withAlphaComponent(0.5)
            }
            return color
        }
    }

    func setImage(_ image: UIImage) {
        guard var configuration = self.innerButton.configuration else { return }
        configuration.image = image
        self.innerButton.configuration = configuration
    }

    func setBackgroundColor(_ color: UIColor) {
        guard let configuration = self.innerButton.configuration else { return }

        var newConfiguration: UIButton.Configuration
        if color == .clear {
            newConfiguration = UIButton.Configuration.plain()
            newConfiguration.image = configuration.image
            setupDefaultConfiguration(&newConfiguration)
        } else {
            newConfiguration = UIButton.Configuration.filled()
            newConfiguration.image = configuration.image
            setupDefaultConfiguration(&newConfiguration)
        }

        newConfiguration.baseBackgroundColor = color

        self.innerButton.configuration = newConfiguration
    }

    func showIndicator() {
        self.activityIndicator.startAnimating()
        self.customView = self.activityIndicator
    }

    func hideIndicator() {
        self.customView = self.innerButton
        self.activityIndicator.stopAnimating()
    }
}
