//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension UIView {
    // From https://stackoverflow.com/a/36388769
    class func fromNib<T: UIView>() -> T {
        // swiftlint:disable:next force_cast
        return Bundle(for: T.self).loadNibNamed(String(describing: T.self), owner: nil, options: nil)![0] as! T
    }

    // https://stackoverflow.com/a/41288197
    // Using a function since `var image` might conflict with an existing variable
    // (like on `UIImageView`)
    func asImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { rendererContext in
            layer.render(in: rendererContext.cgContext)
        }
    }

    @available(iOS 26.0, *)
    @discardableResult
    func addGlassView(withStyle style: UIGlassEffect.Style = .regular) -> UIVisualEffectView {
        self.backgroundColor = .clear

        let effectView = UIVisualEffectView()
        self.insertSubview(effectView, at: 0)

        let glassEffect = UIGlassEffect(style: style)
        effectView.effect = glassEffect
        effectView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            effectView.leftAnchor.constraint(equalTo: self.leftAnchor),
            effectView.rightAnchor.constraint(equalTo: self.rightAnchor),
            effectView.topAnchor.constraint(equalTo: self.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        return effectView
    }
}
