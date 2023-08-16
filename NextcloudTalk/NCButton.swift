//
// Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import UIKit
import SwiftUI

struct NCButtonSwiftUI: View {
    @State var title: String
    @State var action: () -> Void
    @State var style: NCButtonStyle
    @State var height: CGFloat
    @Binding var disabled: Bool

    enum NCButtonStyle: Int {
        case primary = 0
        case secondary
        case tertiary
        case destructive
    }

    var body: some View {
        Button(action: action, label: {
            HStack {
                Spacer()
                Text(title)
                    .bold()
                    .foregroundColor(titleColorForStyle(style: style).opacity(disabled ? 0.75 : 1))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 40)
                    .frame(height: height)
                    .background(backgroundColorForStyle(style: style))
                    .cornerRadius(height / 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(borderColorForStyle(style: style), lineWidth: borderWidthForStyle(style: style))
                    )
                Spacer()
            }
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
        self.layer.cornerRadius = self.frame.height / 2
        self.layer.masksToBounds = true
        self.setButtonStyle(style: .primary)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.layer.cornerRadius = self.frame.height / 2
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
        if let style = self.style {
            self.backgroundColor = enabled ? backgroundColorForStyle(style: style) : backgroundColorForStyle(style: style).withAlphaComponent(0.5)
        }
        self.isEnabled = enabled
    }

    func setButtonAction(target: Any?, selector: Selector) {
        self.removeTarget(target, action: buttonAction, for: .touchUpInside)
        self.addTarget(target, action: selector, for: .touchUpInside)
        buttonAction = selector
    }
}
