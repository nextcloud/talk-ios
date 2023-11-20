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

import Foundation
import NextcloudKit
import PhotosUI
import UIKit

@objcMembers public class InputbarViewController: SLKTextViewController, NCChatTitleViewDelegate {

    // MARK: - Public var
    public var room: NCRoom

    // MARK: - Internal var
    internal var titleView: NCChatTitleView?
    internal var autocompletionUsers: [[String: Any]] = []
    internal var mentionsDict: [String: NCMessageParameter] = [:]
    internal var contentView: UIView?

    public init?(for room: NCRoom, tableViewStyle style: UITableView.Style) {
        self.room = room

        super.init(tableViewStyle: style)

        self.commonInit()
    }

    public init?(for room: NCRoom, withView view: UIView) {
        self.room = room
        self.contentView = view

        super.init(tableViewStyle: .plain)

        self.commonInit()

        view.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(view)

        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor),
            view.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor),
            view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.textInputbar.topAnchor)
        ])

        // Make sure our contentView does not hide the inputBar and the autocompletionView
        self.view.bringSubviewToFront(self.textInputbar)
        self.view.bringSubviewToFront(self.autoCompletionView)
    }

    private func commonInit() {
        self.registerClass(forTextView: NCMessageTextView.self)
        self.registerClass(forReplyView: ReplyMessageView.self)
        self.registerClass(forTypingIndicatorView: TypingIndicatorView.self)
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        print("Dealloc InputbarViewController")
    }

    // MARK: - View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.setTitleView()

        self.bounces = false
        self.shakeToClearEnabled = false

        self.textInputbar.autoHideRightButton = false
        self.textInputbar.counterStyle = .limitExceeded
        self.textInputbar.counterPosition = .top

        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities()

        if serverCapabilities.chatMaxLength > 0 {
            self.textInputbar.maxCharCount = UInt(serverCapabilities.chatMaxLength)
        } else {
            self.textInputbar.maxCharCount = 1000
            self.textInputbar.counterStyle = .countdownReversed
        }

        self.textInputbar.isTranslucent = false
        self.textInputbar.semanticContentAttribute = .forceLeftToRight
        self.textInputbar.contentInset = .init(top: 8, left: 4, bottom: 8, right: 4)
        self.textView.textContainerInset = .init(top: 8, left: 8, bottom: 8, right: 8)

        self.textView.layoutSubviews()
        self.textView.layer.cornerRadius = self.textView.frame.size.height / 2

        self.textInputbar.editorTitle.textColor = .darkGray
        self.textInputbar.editorLeftButton.tintColor = .systemBlue
        self.textInputbar.editorRightButton.tintColor = .systemBlue

        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.tabBarController?.tabBar.tintColor = NCAppBranding.themeColor()

        let themeColor: UIColor = NCAppBranding.themeColor()
        let themeTextColor: UIColor = NCAppBranding.themeTextColor()

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: themeTextColor]
        appearance.backgroundColor = themeColor
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.view.backgroundColor = .systemBackground
        self.textInputbar.backgroundColor = .systemBackground

        self.textInputbar.editorTitle.textColor = .label
        self.textView.layer.borderWidth = 1.0
        self.textView.layer.borderColor = UIColor.systemGray4.cgColor

        // Hide default top border of UIToolbar
        self.textInputbar.setShadowImage(UIImage(), forToolbarPosition: .any)
        self.textView.delegate = self

        self.autoCompletionView.register(AutoCompletionTableViewCell.self, forCellReuseIdentifier: AutoCompletionCellIdentifier)
        self.registerPrefixes(forAutoCompletion: ["@"])

        self.autoCompletionView.backgroundColor = .secondarySystemBackground
        self.autoCompletionView.sectionHeaderTopPadding = 0

        // Align separators to ChatMessageTableViewCell's title label
        self.autoCompletionView.separatorInset = .init(top: 0, left: 50, bottom: 0, right: 0)

        // We can't use UIColor with systemBlueColor directly, because it will switch to indigo. So make sure we actually get a blue tint here
        self.textView.tintColor = UIColor(cgColor: UIColor.systemBlue.cgColor)

        // Markdown formatting options
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityMarkdownMessages) {
            self.textView.registerMarkdownFormattingSymbol("**", withTitle: NSLocalizedString("Bold", comment: "Bold text"))
            self.textView.registerMarkdownFormattingSymbol("_", withTitle: NSLocalizedString("Italic", comment: "Italic text"))
            self.textView.registerMarkdownFormattingSymbol("~~", withTitle: NSLocalizedString("Strikethrough", comment: "Strikethrough text"))
            self.textView.registerMarkdownFormattingSymbol("`", withTitle: NSLocalizedString("Code", comment: "Code block"))
        }

        if let pendingMessage = self.room.pendingMessage {
            self.setChatMessage(pendingMessage)
        }

        self.rightButton.setTitle("", for: .normal)
        self.rightButton.setImage(UIImage(systemName: "paperplane"), for: .normal)
        self.rightButton.accessibilityLabel = NSLocalizedString("Send message", comment: "")
        self.rightButton.accessibilityHint = NSLocalizedString("Double tap to send message", comment: "")
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            // We use a CGColor so we loose the automatic color changing of dynamic colors -> update manually
            self.textView.layer.borderColor = UIColor.systemGray4.cgColor
            self.textView.tintColor = UIColor(cgColor: UIColor.systemBlue.cgColor)
        }
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            self.setTitleView()
        }
    }

    // MARK: - Configuration

    func setTitleView() {
        let titleView = NCChatTitleView()
        titleView.frame = .init(x: 0, y: 0, width: Int.max, height: 30)
        titleView.delegate = self
        titleView.titleTextView.accessibilityHint = NSLocalizedString("Double tap to go to conversation information", comment: "")

        if self.navigationController?.traitCollection.verticalSizeClass == .compact {
            titleView.showSubtitle = false
        }

        titleView.update(for: self.room)
        self.titleView = titleView
        self.navigationItem.titleView = titleView
    }

    // MARK: - Autocompletion

    public override func didChangeAutoCompletionPrefix(_ prefix: String, andWord word: String) {
        if prefix == "@" {
            self.showSuggestions(for: word)
        }
    }

    public override func heightForAutoCompletionView() -> CGFloat {
        return kAutoCompletionCellHeight * CGFloat(self.autocompletionUsers.count)
    }

    func showSuggestions(for string: String) {
        self.autocompletionUsers = []

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getMentionSuggestions(inRoom: self.room.token, for: string, for: activeAccount) { nsMentionsArray, error in
            guard error == nil else { return }

            if let mentionsArray = nsMentionsArray as? [[String: Any]] {
                self.autocompletionUsers = mentionsArray
                let showAutocomplete = !self.autocompletionUsers.isEmpty

                // Check if "@" is still there
                self.textView.look(forPrefixes: self.registeredPrefixes) { prefix, word, _ in
                    if prefix?.count ?? 0 > 0 && word?.count ?? 0 > 0 {
                        self.showAutoCompletionView(showAutocomplete)
                    } else {
                        self.cancelAutoCompletion()
                    }
                }
            }
        }
    }

    internal func replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: String, parameters: String) -> String {
        var resultMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let messageParametersDict = NCMessageParameter.messageParametersDict(fromJSONString: parameters) else { return resultMessage }

        for (parameterKey, parameter) in messageParametersDict {
            let parameterKeyString = "{\(parameterKey)}"
            resultMessage = resultMessage.replacingOccurrences(of: parameter.mentionDisplayName, with: parameterKeyString)
        }

        return resultMessage
    }

    // MARK: - UITableViewDataSource methods

    public override func numberOfSections(in tableView: UITableView) -> Int {
        if tableView == self.autoCompletionView {
            return 1
        }

        return 0
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == self.autoCompletionView {
            return self.autocompletionUsers.count
        }

        return 0
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return nil
    }

    public override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }

    public override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard tableView == self.autoCompletionView,
              indexPath.row < self.autocompletionUsers.count,
              let cell = self.autoCompletionView.dequeueReusableCell(withIdentifier: AutoCompletionCellIdentifier) as? AutoCompletionTableViewCell
        else {
            return AutoCompletionTableViewCell(style: .default, reuseIdentifier: AutoCompletionCellIdentifier)
        }

        let suggestion = self.autocompletionUsers[indexPath.row]

        if let suggestionId = suggestion["id"] as? String,
           let suggestionName = suggestion["label"] as? String,
           let suggestionSource = suggestion["source"] as? String {

            cell.titleLabel.text = suggestionName

            if let suggestionUserStatus = suggestion["status"] as? String {
                cell.setUserStatus(suggestionUserStatus)
            }

            if suggestionId == "all" {
                cell.avatarButton.setAvatar(for: self.room, with: self.traitCollection.userInterfaceStyle)
            } else if suggestionSource == "guests" {
                let name = suggestionName == "Guest" ? "?" : suggestionName
                let image = NCUtils.getImageWith(name, withBackgroundColor: NCAppBranding.placeholderColor(), withBounds: cell.avatarButton.bounds, isCircular: true)
                cell.avatarButton.setImage(image, for: .normal)
            } else if suggestionSource == "groups" {
                cell.avatarButton.setGroupAvatar(with: self.traitCollection.userInterfaceStyle)
            } else {
                cell.avatarButton.setUserAvatar(for: suggestionId, with: self.traitCollection.userInterfaceStyle)
            }
        }

        return cell
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard tableView == self.autoCompletionView,
              indexPath.row < self.autocompletionUsers.count
        else { return }

        let suggestion = self.autocompletionUsers[indexPath.row]
        let mention = NCMessageParameter()

        if let id = suggestion["id"] as? String,
           let label = suggestion["label"] as? String,
           let source = suggestion["source"] as? String {

            mention.parameterId = id
            mention.name = label
            mention.mentionDisplayName = "@\(label)"
            mention.mentionId = "@\(id)"

            // Guest mentions are wrapped with double quotes @"guest/<sha1(webrtc session id)>"
            // Group mentions are wrapped with double quotes @"group/groupId"
            // User-ids with a space should be wrapped in double quoutes
            if source == "guests" || source == "groups" || id.rangeOfCharacter(from: .whitespaces) != nil {
                mention.mentionId = "@\"\(id)\""
            }

            // Set parameter type
            if source == "calls" {
                mention.type = "call"
            } else if source == "users" {
                mention.type = "user"
            } else if source == "guests" {
                mention.type = "guest"
            } else if source == "groups" {
                mention.type = "user-group"
            }

            let mentionKey = "mention-\(self.mentionsDict.count)"
            self.mentionsDict[mentionKey] = mention

            let mentionWithWhitespace = label + " "
            self.acceptAutoCompletion(with: mentionWithWhitespace, keepPrefix: true)
        }
    }

    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return kAutoCompletionCellHeight
    }

    // MARK: - TextView functiosn

    public func setChatMessage(_ chatMessage: String) {
        DispatchQueue.main.async {
            self.textView.text = chatMessage
        }
    }

    public override func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text.isEmpty, let selectedRange = textView.selectedTextRange, let text = textView.text {
            let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
            let substring = (text as NSString).substring(to: cursorOffset)

            if var lastPossibleMention = substring.components(separatedBy: "@").last {
                lastPossibleMention.insert("@", at: lastPossibleMention.startIndex)

                for (mentionKey, mentionParameter) in self.mentionsDict {
                    if lastPossibleMention != mentionParameter.mentionDisplayName {
                        continue
                    }

                    // Delete mention
                    let range = NSRange(location: cursorOffset - lastPossibleMention.count, length: lastPossibleMention.count)
                    textView.text = (text as NSString).replacingCharacters(in: range, with: "")

                    // Only delete it from mentionsDict if there are no more mentions for that user/room
                    // User could have manually added the mention without selecting it from autocompletion
                    // so no mention was added to the mentionsDict
                    if (textView.text as NSString).range(of: lastPossibleMention).location != NSNotFound {
                        self.mentionsDict.removeValue(forKey: mentionKey)
                    }

                    return true
                }
            }
        }

        return super.textView(textView, shouldChangeTextIn: range, replacementText: text)
    }

    // MARK: - TitleView delegate

    public func chatTitleViewTapped(_ titleView: NCChatTitleView!) {
        // Doing nothing here -> override in subclass
    }

}
