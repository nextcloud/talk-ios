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

@objcMembers class ReferenceView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet var referenceView: UIView!
    @IBOutlet weak var activityIndicatorView: UIView!

    var activityIndicator: MDCActivityIndicator = MDCActivityIndicator(frame: CGRect(x: 0, y: 0, width: 50, height: 50))

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("ReferenceView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        activityIndicator.radius = 12.0
        activityIndicator.cycleColors = [UIColor.lightGray]

        showIndicatorView()

        activityIndicatorView.addSubview(activityIndicator)

        layer.cornerRadius = 8.0
        layer.masksToBounds = true
        layer.borderWidth = 1.0
        layer.borderColor = NCAppBranding.placeholderColor().cgColor

        self.addSubview(contentView)
    }

    func prepareForReuse() {
        referenceView.subviews.forEach({ $0.removeFromSuperview() })
        showIndicatorView()
    }

    func showIndicatorView() {
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
    }

    func hideIndicatorView() {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
    }

    func showErrorView(for url: String) {
        let defaultView = ReferenceDefaultView(frame: self.frame)
        defaultView.update(for: nil, and: url)
        defaultView.frame = self.bounds
        defaultView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceView.addSubview(defaultView)
    }

    func update(for sharedDeckCard: NCDeckCardParameter) {
        let deckView = ReferenceDeckView(frame: self.frame)
        deckView.update(for: sharedDeckCard)
        deckView.frame = self.bounds
        deckView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceView.addSubview(deckView)
        self.hideIndicatorView()
    }

    func update(for references: [String: [String: AnyObject]]?, and url: String) {
        referenceView.subviews.forEach({ $0.removeFromSuperview() })

        guard let references = references,
              !references.isEmpty else {

            showErrorView(for: url)
            hideIndicatorView()
            return
        }

        let referenceArray = Array(references.values)
        let firstReference = referenceArray[0]

        let richObjectType = firstReference["richObjectType"] as? String

        var foundReferenceView = false

        if richObjectType == "integration_github" || richObjectType == "integration_github_issue_pr",
           let reference = firstReference["richObject"] as? [String: AnyObject] {

            let githubView = ReferenceGithubView(frame: self.frame)
            githubView.update(for: reference, and: url)
            githubView.frame = self.bounds
            githubView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            referenceView.addSubview(githubView)
            foundReferenceView = true
        } else if richObjectType == "deck-card",
                  let reference = firstReference["richObject"] as? [String: AnyObject] {

            let deckView = ReferenceDeckView(frame: self.frame)
            deckView.update(for: reference, and: url)
            deckView.frame = self.bounds
            deckView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            referenceView.addSubview(deckView)
            foundReferenceView = true
        } else if let reference = firstReference["openGraphObject"] as? [String: String?] {
            let defaultView = ReferenceDefaultView(frame: self.frame)
            defaultView.update(for: reference, and: url)
            defaultView.frame = self.bounds
            defaultView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            referenceView.addSubview(defaultView)
            foundReferenceView = true
        }

        if !foundReferenceView {
            showErrorView(for: url)
        }

        hideIndicatorView()
    }
}
