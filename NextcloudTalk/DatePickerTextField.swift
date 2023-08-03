//
// Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
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

@objcMembers class DatePickerTextField: UITextField {

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

    public func getDate(completion: @escaping (Date) -> Void) {
        guard self.canBecomeFirstResponder else {
            return
        }

        datePicker.datePickerMode = .dateAndTime
        datePicker.locale = .current
        datePicker.preferredDatePickerStyle = .wheels

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
