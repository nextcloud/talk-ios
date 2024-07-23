//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers class CallReactionView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var reactionLabel: UILabel!
    @IBOutlet weak var actorLabelView: UIView!
    @IBOutlet weak var actorLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("CallReactionView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = frame
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        actorLabelView.layer.cornerRadius = 4.0
        actorLabelView.layer.shadowOpacity = 0.8
        actorLabelView.layer.shadowOffset = CGSize(width: 2.0, height: 2.0)
    }

    func setReaction(reaction: String, actor: String) {
        reactionLabel.text = reaction
        actorLabel.text = actor
        actorLabelView.backgroundColor = ColorGenerator.shared.usernameToColor(actor)
    }
}
