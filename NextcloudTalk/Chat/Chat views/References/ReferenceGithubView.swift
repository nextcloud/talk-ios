//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
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
            NCUtils.openLinkInBrowser(link: url)
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
