//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

class DatePickerTextField: UITextField {

    public let datePicker = UIDatePicker()

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

    public func getDate(startingDate: Date?, minimumDate: Date?, completion: @escaping (Date) -> Void) {
        guard self.canBecomeFirstResponder else {
            return
        }

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

        let cancelButton = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.resignFirstResponder()
        })

        let doneButton = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            if let self {
                completion(self.datePicker.date)
                self.resignFirstResponder()
            }
        })

        let toolBar = UIToolbar(frame: .init(x: 0, y: 0, width: 320, height: 44))
        toolBar.setItems([cancelButton, UIBarButtonItem(systemItem: .flexibleSpace), doneButton], animated: false)

        self.inputAccessoryView = toolBar

        self.becomeFirstResponder()
    }
}
