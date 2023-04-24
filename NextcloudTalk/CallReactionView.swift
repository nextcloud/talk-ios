//
// Copyright (c) 2023 Ivan Sein <ivan@nextcloud.com>
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

@objcMembers class CallReactionView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var reactionLabel: UILabel!
    @IBOutlet weak var actorLabelView: UIView!
    @IBOutlet weak var actorLabel: UILabel!

    @IBOutlet weak var labelLeftPadding: NSLayoutConstraint!
    @IBOutlet weak var labelRightPadding: NSLayoutConstraint!
    @IBOutlet weak var labelViewRightPadding: NSLayoutConstraint!

    @IBOutlet weak var reactionTopPadding: NSLayoutConstraint!
    @IBOutlet weak var reactionBottomPadding: NSLayoutConstraint!

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

    func expectedSize() -> CGSize {
        let expectedLabelWidth = actorLabel.text?.width(withConstrainedHeight: frame.height, font: actorLabel.font) ?? 0
        let expectedReactionWidth = actorLabelView.frame.origin.x + labelLeftPadding.constant + labelRightPadding.constant + expectedLabelWidth + labelViewRightPadding.constant
        let expectedReactionHeight = reactionTopPadding.constant + reactionLabel.frame.height + reactionBottomPadding.constant

        return CGSize(width: expectedReactionWidth, height: expectedReactionHeight)
    }
}
