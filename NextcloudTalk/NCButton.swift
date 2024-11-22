//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit
import SwiftUI

let NCButtonHorizontalPadding: CGFloat = 16
let NCButtonVerticalPadding: CGFloat = 8
let NCButtonCornerRadius: CGFloat = 8

struct NCButtonSwiftUI: View {
    @State var title: String
    @State var action: () -> Void
    @State var style: NCButtonStyle
    @Binding var disabled: Bool

    enum NCButtonStyle: Int {
        case primary = 0
        case secondary
        case tertiary
        case destructive
    }

    var body: some View {
        Button(action: action, label: {
                Text(title)
                    .bold()
                    .foregroundColor(titleColorForStyle(style: style).opacity(disabled ? 0.5 : 1))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, NCButtonVerticalPadding)
                    .padding(.horizontal, NCButtonHorizontalPadding)
                    .background(backgroundColorForStyle(style: style).opacity(disabled ? 0.5 : 1))
                    .cornerRadius(NCButtonCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: NCButtonCornerRadius)
                            .stroke(borderColorForStyle(style: style).opacity(disabled ? 0.5 : 1), lineWidth: borderWidthForStyle(style: style))
                    )
        })
        .disabled(disabled)
    }

    func backgroundColorForStyle(style: NCButtonStyle) -> Color {
        switch style {
        case .primary:
            return Color(NCAppBranding.themeColor())
        case .secondary:
            return .clear
        case .tertiary:
            return .clear
        case .destructive:
            return .red
        }
    }

    func titleColorForStyle(style: NCButtonStyle) -> Color {
        switch style {
        case .primary:
            return Color(NCAppBranding.themeTextColor())
        case .secondary:
            return Color(NCAppBranding.elementColor())
        case .tertiary:
            return .primary
        case .destructive:
            return .white
        }
    }

    func borderColorForStyle(style: NCButtonStyle) -> Color {
        switch style {
        case .primary:
            return .clear
        case .secondary:
            return Color(NCAppBranding.elementColor())
        case .tertiary:
            return Color(NCAppBranding.placeholderColor())
        case .destructive:
            return .clear
        }
    }

    func borderWidthForStyle(style: NCButtonStyle) -> CGFloat {
        switch style {
        case .primary:
            return 0.0
        case .secondary:
            return 1.0
        case .tertiary:
            return 1.0
        case .destructive:
            return 0.0
        }
    }
}

@objc class NCButton: UIButton {

    enum NCButtonStyle: Int {
        case primary = 0
        case secondary
        case tertiary
        case destructive
    }

    var style: NCButtonStyle?
    var buttonAction: Selector?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        self.configuration = UIButton.Configuration.plain()
        self.configuration?.contentInsets = .init(top: NCButtonVerticalPadding, leading: NCButtonHorizontalPadding, bottom: NCButtonVerticalPadding, trailing: NCButtonHorizontalPadding)
        self.layer.cornerRadius = NCButtonCornerRadius
        self.layer.masksToBounds = true
        self.setButtonStyle(style: .primary)
    }

    func backgroundColorForStyle(style: NCButtonStyle) -> UIColor {
        switch style {
        case .primary:
            return NCAppBranding.themeColor()
        case .secondary:
            return .clear
        case .tertiary:
            return .clear
        case .destructive:
            return .systemRed
        }
    }

    func setButtonStyle(style: NCButtonStyle) {
        self.style = style
        switch style {
        case .primary:
            self.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
            self.setTitleColor(NCAppBranding.themeTextColor().withAlphaComponent(0.5), for: .disabled)
            self.backgroundColor = backgroundColorForStyle(style: .primary)
            self.layer.borderWidth = 0.0
        case .secondary:
            self.setTitleColor(NCAppBranding.elementColor(), for: .normal)
            self.setTitleColor(NCAppBranding.elementColor().withAlphaComponent(0.5), for: .disabled)
            self.backgroundColor = backgroundColorForStyle(style: .secondary)
            self.layer.borderColor = NCAppBranding.elementColor().cgColor
            self.layer.borderWidth = 1.0
        case .tertiary:
            self.setTitleColor(.label, for: .normal)
            self.setTitleColor(.label.withAlphaComponent(0.5), for: .disabled)
            self.backgroundColor = backgroundColorForStyle(style: .tertiary)
            self.layer.borderColor = NCAppBranding.placeholderColor().cgColor
            self.layer.borderWidth = 1.0
        case .destructive:
            self.setTitleColor(.white, for: .normal)
            self.setTitleColor(.white.withAlphaComponent(0.5), for: .disabled)
            self.backgroundColor = backgroundColorForStyle(style: .destructive)
            self.layer.borderWidth = 0.0
        }
    }

    func setButtonEnabled(enabled: Bool) {
        if let style = self.style, backgroundColorForStyle(style: style) != .clear {
            self.backgroundColor = enabled ? backgroundColorForStyle(style: style) : backgroundColorForStyle(style: style).withAlphaComponent(0.5)
        }
        if let borderColor = self.layer.borderColor {
            self.layer.borderColor = UIColor(cgColor: borderColor).withAlphaComponent(enabled ? 1 : 0.5).cgColor
        }
        self.isEnabled = enabled
    }

    func setButtonAction(target: Any?, selector: Selector) {
        self.removeTarget(target, action: buttonAction, for: .touchUpInside)
        self.addTarget(target, action: selector, for: .touchUpInside)
        buttonAction = selector
    }
}
