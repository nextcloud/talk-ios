//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct RoomInfoGuestPasswordSave: View {

    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var message: String = ""
    @State private var messageColor: Color = .secondary
    @State private var isSaveEnabled: Bool = false
    @State private var validationTask: Task<Void, Never>?

    var trimmedPassword: String {
        return password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum Field {
        case password
    }
    @FocusState private var focusedField: Field?

    // MARK: - Configuration

    let minLength: Int
    let isPasswordValidationRequired: Bool
    let onSave: (String) -> Void

    // MARK: - View

    var body: some View {
        HStack {
            VStack {
                Image(systemName: "key").foregroundStyle(.secondary).frame(width: 24, height: 32)
                Spacer()
            }
            VStackLayout(alignment: .leading) {
                HStack {
                    // Password fields
                    Group {
                        if isPasswordVisible {
                            TextField(
                                NSLocalizedString("Enter a password", comment: ""),
                                text: $password
                            )
                            .focused($focusedField, equals: .password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        } else {
                            SecureField(
                                NSLocalizedString("Enter a password", comment: ""),
                                text: $password
                            )
                            .focused($focusedField, equals: .password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: password) { newValue in
                        passwordChanged(to: newValue)
                    }

                    // Eye toggle button
                    Button {
                        isPasswordVisible.toggle()
                        DispatchQueue.main.async {
                            focusedField = .password
                        }
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye" : "eye.slash")
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }

                // Validation reason
                Text(message)
                    .font(.footnote)
                    .foregroundColor(messageColor)

                HStack {
                    // Save button
                    Button(NSLocalizedString("Save password", comment: "")) {
                        onSave(trimmedPassword)
                        resetValues()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isSaveEnabled ? Color.green : Color.gray.opacity(0.3))
                    .clipShape(Capsule())
                    .disabled(!isSaveEnabled)

                    // Copy button
                    Button {
                        UIPasteboard.general.string = password
                        NotificationPresenter.shared().present(text: NSLocalizedString("Password copied", comment: ""), dismissAfterDelay: 5.0, includedStyle: .dark)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .background(isSaveEnabled ? Color.blue : Color.gray.opacity(0.3))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .disabled(!isSaveEnabled)
                }
            }
            .onAppear {
                setDefaultMessage()
                focusedField = .password
            }
        }
    }

    func resetValues() {
        validationTask?.cancel()
        password = ""
        isPasswordVisible = false
        setDefaultMessage()
    }

    func setDefaultMessage() {
        message = ""
        messageColor = .secondary
        isSaveEnabled = false
    }

    func setMinLengthMessage() {
        message = String.localizedStringWithFormat(NSLocalizedString("Password needs to be at least %d characters long", comment: ""), minLength)
        messageColor = .red
        isSaveEnabled = false
    }

    @MainActor
    func passwordChanged(to newValue: String) {
        validationTask?.cancel()
        isSaveEnabled = false

        // Empty password field
        if trimmedPassword.isEmpty {
            setDefaultMessage()
            return
        }

        // Password does not have minimum length
        if trimmedPassword.count < minLength {
            setMinLengthMessage()
            return
        }

        // No password validation required
        if !isPasswordValidationRequired {
            setDefaultMessage()
            isSaveEnabled = true
            return
        }

        // Validate password if password policy app is enabled
        validationTask = Task { [trimmedPassword] in
            // Debounce
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            message = NSLocalizedString("Validating password…", comment: "")
            messageColor = .secondary

            do {
                let result = try await NCAPIController.sharedInstance()
                    .validatePassword(password: trimmedPassword, forAccount: NCDatabaseManager.sharedInstance().activeAccount())
                if result.passed {
                    message = NSLocalizedString("Password is secure", comment: "")
                    messageColor = .green
                } else {
                    message = result.reason ?? ""
                    messageColor = .red
                }
                isSaveEnabled = result.passed
            } catch {
                await MainActor.run {
                    isSaveEnabled = false
                    message = NSLocalizedString("Unable to validate password right now", comment: "")
                }
            }
        }
    }
}
