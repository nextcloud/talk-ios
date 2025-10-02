//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import Foundation
import SwiftyAttributes

@objcMembers class GithubPermalinkViewController: UIViewController, UIScrollViewDelegate {

    @IBOutlet public weak var sourceWithNumbersTextView: UITextView!
    @IBOutlet public weak var sourceWithNumbersScrollView: UIScrollView!
    @IBOutlet public weak var sourceWithoutNumbersTextView: UITextView!
    @IBOutlet public weak var sourceWithoutNumbersScrollView: UIScrollView!
    @IBOutlet public weak var ownerLabel: UILabel!
    @IBOutlet public weak var repoLabel: UILabel!
    @IBOutlet public weak var fileLabel: UILabel!
    @IBOutlet public weak var scrollViewLeftConstraint: NSLayoutConstraint!

    private var url: String?
    private var sourceWithLineNumbers = NSAttributedString()
    private var sourceWithoutLineNumbers = NSAttributedString()
    private var owner = ""
    private var repo = ""
    private var filePath = ""
    private var lineNumberWidth: CGFloat = 0

    init(url: String,
         sourceWithLineNumbers: NSAttributedString,
         sourceWithoutLineNumbers: NSAttributedString,
         owner: String,
         repo: String,
         filePath: String,
         lineNumberWidth: CGFloat) {

        super.init(nibName: "GithubPermalinkViewController", bundle: nil)

        self.url = url
        self.sourceWithLineNumbers = sourceWithLineNumbers
        self.sourceWithoutLineNumbers = sourceWithoutLineNumbers
        self.owner = owner
        self.repo = repo
        self.filePath = filePath
        self.lineNumberWidth = lineNumberWidth
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Source code", comment: "")

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        if #unavailable(iOS 26.0) {
            self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        }

        let githubButton = UIBarButtonItem(image: UIImage(named: "github")?.withRenderingMode(.alwaysTemplate), style: .plain, target: self, action: #selector(githubButtonPressed))
        self.navigationItem.rightBarButtonItem = githubButton

        if #unavailable(iOS 26.0) {
            self.navigationItem.rightBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        } else {
            self.navigationItem.rightBarButtonItem?.tintColor = .label
        }

        let font = Font.systemFont(ofSize: 16)
        let fontSemibold = Font.systemFont(ofSize: 16, weight: .semibold)

        self.sourceWithNumbersTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        self.sourceWithoutNumbersTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        self.sourceWithNumbersScrollView.layer.cornerRadius = 8
        self.sourceWithoutNumbersScrollView.layer.cornerRadius = 8

        self.sourceWithNumbersScrollView.layer.masksToBounds = true
        self.sourceWithoutNumbersScrollView.layer.masksToBounds = true

        self.sourceWithNumbersTextView.textContainer.lineFragmentPadding = 0
        self.sourceWithoutNumbersTextView.textContainer.lineFragmentPadding = 0

        self.sourceWithNumbersTextView.attributedText = sourceWithLineNumbers
        self.sourceWithoutNumbersTextView.attributedText = sourceWithoutLineNumbers

        // Set the delgate to synchronize scrolling
        self.sourceWithoutNumbersScrollView.delegate = self

        // We have to reduce the size of our overlaying view depending on how big the line numbers are
        // Take safe-area padding of 10 into account here
        self.scrollViewLeftConstraint.constant = self.lineNumberWidth + 10

        var formattedOwner = NSLocalizedString("Owner", comment: "Owner of a repository").attributedString + ": ".attributedString
        formattedOwner = formattedOwner.withFont(fontSemibold).withTextColor(.secondaryLabel)
        formattedOwner +=  self.owner.withFont(font)
        self.ownerLabel.attributedText = formattedOwner

        var formattedRepo = NSLocalizedString("Repo", comment: "Name of a repository").attributedString + ": ".attributedString
        formattedRepo = formattedRepo.withFont(fontSemibold).withTextColor(.secondaryLabel)
        formattedRepo += self.repo.withFont(font)
        self.repoLabel.attributedText = formattedRepo

        var formattedPath = NSLocalizedString("File", comment: "Filename of a file").attributedString + ": ".attributedString
        formattedPath = formattedPath.withFont(fontSemibold).withTextColor(.secondaryLabel)
        formattedPath += self.filePath.withFont(font)
        self.fileLabel.attributedText = formattedPath
    }

    func githubButtonPressed() {
        if let url = self.url {
            NCUtils.openLinkInBrowser(link: url)
        }
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.sourceWithNumbersTextView.contentOffset = CGPoint(x: 0, y: self.sourceWithoutNumbersScrollView.contentOffset.y)
    }
}
