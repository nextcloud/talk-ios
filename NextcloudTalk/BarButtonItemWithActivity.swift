//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

class BarButtonItemWithActivity: UIBarButtonItem {

    var innerButton = UIButton()
    var activityIndicator = UIActivityIndicatorView()

    init(image: UIImage) {
        super.init()

        let themeTextColor = NCAppBranding.themeTextColor()

        var configuration = UIButton.Configuration.filled()
        configuration.image = image
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = themeTextColor

        self.innerButton.configuration = configuration

        self.activityIndicator.color = themeTextColor
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

    func setImage(_ image: UIImage) {
        guard var configuration = self.innerButton.configuration else { return }
        configuration.image = image
        self.innerButton.configuration = configuration
    }

    func setBackgroundColor(_ color: UIColor) {
        guard var configuration = self.innerButton.configuration else { return }
        configuration.baseBackgroundColor = color
        self.innerButton.configuration = configuration
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
