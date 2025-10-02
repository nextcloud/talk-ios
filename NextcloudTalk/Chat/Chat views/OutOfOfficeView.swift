//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Combine
import SwiftyAttributes

@objcMembers class OutOfOfficeView: UIView, UIGestureRecognizerDelegate {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var leftIndicator: UIView!
    @IBOutlet weak var backgroundView: UIView!
    @IBOutlet weak var wrapperView: UIView!
    @IBOutlet weak var stackView: UIStackView!

    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var dates: UILabel!
    @IBOutlet weak var replacement: UILabel!
    @IBOutlet weak var subtitle: UITextView!

    @IBOutlet weak var uiMenuButton: UIButton!

    private var tapToShowMenu: UITapGestureRecognizer?

    public var maxNumberOfLines: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("OutOfOfficeView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = frame
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.backgroundColor = .systemGroupedBackground

        leftIndicator.backgroundColor = NCAppBranding.themeColor()
        backgroundView.backgroundColor = NCAppBranding.themeColor().withAlphaComponent(0.3)
        wrapperView.backgroundColor = .systemGroupedBackground
        wrapperView.layer.cornerRadius = 8
        wrapperView.layer.masksToBounds = true

        subtitle.textContainerInset = .zero
        subtitle.textContainer.lineFragmentPadding = 0

        uiMenuButton.showsMenuAsPrimaryAction = true

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapTextView))
        self.tapToShowMenu = tapGestureRecognizer
        tapGestureRecognizer.delegate = self
        tapGestureRecognizer.require(toFail: subtitle.panGestureRecognizer)

        subtitle.addGestureRecognizer(tapGestureRecognizer)
        stackView.addGestureRecognizer(tapGestureRecognizer)
    }

    func tapTextView() {
        let gestureRecognizer = self.uiMenuButton.gestureRecognizers?.first(where: { $0.description.contains("UITouchDownGestureRecognizer") })
        gestureRecognizer?.touchesBegan([], with: UIEvent())
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    public func setupAbsence(withData absenceData: CurrentUserAbsence, inRoom room: NCRoom) {
        translatesAutoresizingMaskIntoConstraints = false
        title.text = String.localizedStringWithFormat(NSLocalizedString("%@ is out of office", comment: "'%@' is the name of a user"), room.displayName)

        let dismissAction = UIAction(title: NSLocalizedString("Hide", comment: ""), image: UIImage(systemName: "eye.slash")) { [unowned self] _ in
            self.removeFromSuperview()
        }

        var menuActions = [dismissAction]

        if let startDateTimestamp = absenceData.startDate, let endDateTimestamp = absenceData.endDate {
            let startDate = Date(timeIntervalSince1970: TimeInterval(startDateTimestamp))
            let endDate = Date(timeIntervalSince1970: TimeInterval(endDateTimestamp))

            let isSameDay = Calendar.current.isDate(startDate, inSameDayAs: endDate)
            if isSameDay {
                title.text = String.localizedStringWithFormat(NSLocalizedString("%@ is out of office today", comment: "'%@' is the name of a user"), room.displayName)
                dates.isHidden = true
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .none
                dateFormatter.locale = Locale.current

                let startDateString = dateFormatter.string(from: startDate)
                let endDateString = dateFormatter.string(from: endDate)

                dates.text = "\(startDateString) - \(endDateString)"
            }
        } else {
            dates.isHidden = true
        }

        if let replacementUserId = absenceData.replacementUserId, let replacementUserDisplayname = absenceData.replacementUserDisplayName,
           !replacementUserId.isEmpty, !replacementUserDisplayname.isEmpty {

            let replacementString = NSLocalizedString("Replacement", comment: "Replacement in case of out of office").withFont(.preferredFont(forTextStyle: .body))
            let separatorString = ": ".withFont(.preferredFont(forTextStyle: .body))
            let usernameString = replacementUserDisplayname.withFont(.preferredFont(for: .body, weight: .bold))

            replacement.attributedText = replacementString + separatorString + usernameString

            if let account = room.account, replacementUserId != account.userId, replacementUserId != absenceData.userId {
                let talkIcon = UIImage(named: "talk-20")?.withRenderingMode(.alwaysTemplate)
                menuActions.append(UIAction(title: NSLocalizedString("Talk to", comment: "Talk to a user") + " " + replacementUserDisplayname, image: talkIcon) { [unowned self] _ in
                    NotificationCenter.default.post(name: .NCChatViewControllerTalkToUserNotification, object: self, userInfo: ["actorId": replacementUserId])
                })
            }
        } else {
            replacement.isHidden = true
        }

        if let longNote = absenceData.message {
            subtitle.text = longNote
        } else {
            subtitle.isHidden = true
        }

        uiMenuButton.menu = UIMenu(children: menuActions)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let font = subtitle.font else { return }

        let singleLineHeight = ceil(font.lineHeight + font.leading)
        let maxViewHeight = singleLineHeight * maxNumberOfLines
        let maxTextSize = ceil(subtitle.sizeThatFits(CGSize(width: subtitle.frame.width, height: CGFloat.greatestFiniteMagnitude)).height)

        if maxTextSize > maxViewHeight {
            subtitle.isScrollEnabled = true

            // We want to indicate that the text is scrollable, so show parts of the next line
            let newHeightConstant = maxViewHeight + (singleLineHeight / 2)
            subtitle.heightAnchor.constraint(equalToConstant: newHeightConstant).isActive = true
        } else {
            subtitle.isScrollEnabled = false
            subtitle.heightAnchor.constraint(equalToConstant: maxViewHeight).isActive = false
        }
    }
}
