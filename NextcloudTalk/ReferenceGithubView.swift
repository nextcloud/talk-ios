//
// Copyright (c) 2022 Marcel Müller <marcel-mueller@gmx.de>
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

@objcMembers class ReferenceGithubView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var referenceTypeIcon: UIImageView!
    @IBOutlet weak var referenceTitle: UILabel!
    @IBOutlet weak var referenceBody: UITextView!
    @IBOutlet weak var referenceCommentCount: UILabel!
    @IBOutlet weak var referenceCommentIcon: UIImageView!

    var url: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("ReferenceGithubView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceTitle.text = ""
        referenceBody.text = ""
        referenceTypeIcon.image = nil

        // Remove padding from textView and adjust lineBreakMode
        referenceBody.textContainerInset = .zero
        referenceBody.textContainer.lineFragmentPadding = .zero
        referenceBody.textContainer.lineBreakMode = .byTruncatingTail
        referenceBody.textContainer.maximumNumberOfLines = 3

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
        contentView.addGestureRecognizer(tap)

        self.addSubview(contentView)
    }

    func handleTap() {
        if let url = url {
            NCUtils.openLink(inBrowser: url)
        }
    }

    func setIcon(for reference: [String: AnyObject]) {
        let type = reference["github_type"] as? String
        let state = reference["state"] as? String
        let stateReason = reference["state_reason"] as? String

        var image: UIImage? = UIImage(named: "github-issue-open")?.withTintColor(UIColor.systemGreen)

        if type == "issue" {
            if state == "closed" {
                if stateReason == "not_planned" {
                    image = UIImage(named: "github-issue-notplanned")?.withTintColor(UIColor.systemGray)
                } else {
                    image = UIImage(named: "github-issue-closed")?.withTintColor(UIColor.systemPurple)
                }
            }

        } else if type == "pull_request" || type == "pr" {
            image = UIImage(named: "github-pr-open")?.withTintColor(UIColor.systemGreen)

            if state == "open" {
                if reference["draft"] as? Bool == true {
                    image = UIImage(named: "github-pr-draft")?.withTintColor(UIColor.systemGray)
                }
            } else if state == "closed" {
                if reference["merged"] as? Bool == true {
                    image = UIImage(named: "github-pr-merged")?.withTintColor(UIColor.systemPurple)
                } else {
                    image = UIImage(named: "github-pr-closed")?.withTintColor(UIColor.systemRed)
                }
            }
        }

        if image != nil {
            referenceTypeIcon.image = image
        }
    }

    func update(for reference: [String: AnyObject], and url: String) {
        self.url = url

        if let type = reference["github_type"] as? String {
            if type == "pr-error" || type == "issue-error" {
                referenceTitle.text = NSLocalizedString("GitHub API error", comment: "")

                if let bodyDict = reference["body"] as? [String: String],
                    let body = bodyDict["message"] {

                    referenceBody.text = body
                } else {
                    referenceBody.text = NSLocalizedString("Unknown error", comment: "")
                }

                referenceCommentCount.isHidden = true
                referenceCommentIcon.isHidden = true

                referenceTypeIcon.image = UIImage(named: "github")?.withTintColor(UIColor.systemGray)

                return
            }
        }

        setIcon(for: reference)

        referenceCommentCount.isHidden = false
        referenceCommentIcon.isHidden = false

        if let comments = reference["comments"] as? Int {
            referenceCommentCount.text = String(comments)
        } else {
            referenceCommentCount.text = "0"
        }

        if let title = reference["title"] as? String {
            referenceTitle.text = title
        }

        if let body = reference["body"] as? String {
            referenceBody.text = body
        } else {
            referenceBody.text = NSLocalizedString("No description provided", comment: "")
        }
    }
}
