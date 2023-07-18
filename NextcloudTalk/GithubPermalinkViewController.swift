//
// Copyright (c) 2023 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Marcel Müller <marcel.mueller@nextcloud.com>
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

import UIKit
import Foundation
import SwiftyAttributes

@objcMembers class GithubPermalinkViewController: UIViewController, UITextViewDelegate {

    @IBOutlet public weak var sourceWithNumbersTextView: UITextView!
    @IBOutlet public weak var sourceWithoutNumbersTextView: UITextView!
    @IBOutlet public weak var ownerLabel: UILabel!
    @IBOutlet public weak var repoLabel: UILabel!
    @IBOutlet public weak var fileLabel: UILabel!
    @IBOutlet public weak var sourceCodeLeftConstraint: NSLayoutConstraint!
    @IBOutlet public weak var lineNumbersRightConstraint: NSLayoutConstraint!

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

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Source code", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()

        let githubButton = UIBarButtonItem(image: UIImage(named: "github")?.withRenderingMode(.alwaysTemplate), style: .plain, target: self, action: #selector(githubButtonPressed))
        self.navigationItem.rightBarButtonItem = githubButton
        self.navigationItem.rightBarButtonItem?.tintColor = NCAppBranding.themeTextColor()

        let font = Font.systemFont(ofSize: 16)
        let fontSemibold = Font.systemFont(ofSize: 16, weight: .semibold)

        self.sourceWithNumbersTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        self.sourceWithoutNumbersTextView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        self.sourceWithNumbersTextView.layer.cornerRadius = 8
        self.sourceWithoutNumbersTextView.layer.cornerRadius = 8

        self.sourceWithNumbersTextView.textContainer.lineFragmentPadding = 0
        self.sourceWithoutNumbersTextView.textContainer.lineFragmentPadding = 0

        self.sourceWithNumbersTextView.attributedText = sourceWithLineNumbers
        self.sourceWithoutNumbersTextView.attributedText = sourceWithoutLineNumbers

        // Set the delgate to synchronize scrolling
        self.sourceWithoutNumbersTextView.delegate = self

        // We have to reduce the size of our overlaying view depending on how big the line numbers are
        // Take safe-area padding of 10 into account here
        self.sourceCodeLeftConstraint.constant = self.lineNumberWidth + 10

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
            NCUtils.openLink(inBrowser: url)
        }
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.sourceWithNumbersTextView.contentOffset = self.sourceWithoutNumbersTextView.contentOffset
    }
}
