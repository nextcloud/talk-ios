//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

enum DatePickerTextFieldButtonStyle {
    case cancelAndDone
    case removeAndDone
}

enum DatePickerTextFieldButtonTapped {
    case cancel
    case remove
    case done
}

struct DatePickerTextFieldWrapper: UIViewRepresentable {
    @State var placeholder: String
    @State var minimumDate: Date?
    @State var startingDate: Date?
    @State var buttons: DatePickerTextFieldButtonStyle

    var completion: ((_ buttonTapped: DatePickerTextFieldButtonTapped, _ selectedDate: Date?) -> Void)?

    func makeUIView(context: Context) -> DatePickerTextField {
        let textField = DatePickerTextField()
        textField.textAlignment = .right
        return textField
    }

    func updateUIView(_ uiView: DatePickerTextField, context: Context) {
        uiView.placeholder = placeholder
        uiView.setupDatePicker(startingDate: startingDate, minimumDate: minimumDate, buttons: buttons)
        uiView.completion = completion
    }
}

@objcMembers class DatePickerTextField: UITextField {

    public let datePicker = UIDatePicker()

    public var completion: ((_ buttonTapped: DatePickerTextFieldButtonTapped, _ selectedDate: Date?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        self.commonInit()
    }

    private func commonInit() {
        self.tintColor = .clear
    }

    public func setupDatePicker(startingDate: Date?, minimumDate: Date?, buttons: DatePickerTextFieldButtonStyle = .cancelAndDone) {
        datePicker.datePickerMode = .dateAndTime
        datePicker.locale = .current
        datePicker.preferredDatePickerStyle = .wheels

        if let startingDate {
            datePicker.date = startingDate
        }

        if let minimumDate {
            datePicker.minimumDate = minimumDate
        }

        self.inputView = datePicker

        var leftButton: UIBarButtonItem

        if buttons == .cancelAndDone {
            leftButton = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
                guard let self else { return }

                self.completion?(.cancel, nil)
                self.resignFirstResponder()
            })
        } else {
            leftButton = UIBarButtonItem(title: NSLocalizedString("Remove", comment: ""), primaryAction: UIAction { [weak self] _ in
                guard let self else { return }

                self.completion?(.remove, nil)
                self.resignFirstResponder()
            })

            leftButton.tintColor = .systemRed
        }

        let doneButton = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }

            self.completion?(.done, self.datePicker.date)
            self.resignFirstResponder()
        })

        let toolBar = UIToolbar(frame: .init(x: 0, y: 0, width: 320, height: 44))
        toolBar.setItems([leftButton, UIBarButtonItem(systemItem: .flexibleSpace), doneButton], animated: false)

        self.inputAccessoryView = toolBar
    }

    public func getDate(completion: @escaping (_ buttonTapped: DatePickerTextFieldButtonTapped, _ selectedDate: Date?) -> Void) {
        guard self.canBecomeFirstResponder else {
            return
        }

        self.completion = completion
        self.becomeFirstResponder()
    }
}
