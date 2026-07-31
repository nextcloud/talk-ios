//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

class ReferenceView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet var referenceView: UIView!
    @IBOutlet weak var activityIndicatorView: UIView!

    var activityIndicator: MDCActivityIndicator = MDCActivityIndicator(frame: CGRect(x: 0, y: 0, width: 50, height: 50))

    /// A filled card instead of a hairline border, which used the very same translucent colour and so
    /// would have doubled up. White in both appearances, so the card reads as a panel *lighter* than the
    /// bubble – the semantic fills darken instead. Light mode needs the higher alpha, starting lighter.
    private static let backgroundFill = UIColor { traitCollection in
        let alpha = traitCollection.userInterfaceStyle == .dark ? 0.10 : 0.65

        return UIColor.white.withAlphaComponent(alpha)
    }

    private var aspectRatioConstraint: NSLayoutConstraint?

    /// Sizes the card to an aspect ratio rather than letting it stretch across the message, or restores
    /// the full width when passed nil. Only the GIF uses this – card beside a GIF is just empty fill.
    func setAspectRatio(_ aspectRatio: CGFloat?) {
        self.aspectRatioConstraint?.isActive = false
        self.aspectRatioConstraint = nil

        guard let aspectRatio, aspectRatio > 0 else { return }

        // Outranks the low priority stretch in BaseChatTableViewCell, gives way to the width available
        let constraint = self.widthAnchor.constraint(equalTo: self.heightAnchor, multiplier: aspectRatio)
        constraint.priority = .defaultHigh
        constraint.isActive = true

        self.aspectRatioConstraint = constraint
    }

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

        backgroundColor = ReferenceView.backgroundFill

        self.addSubview(contentView)
    }

    func prepareForReuse() {
        referenceView.subviews.forEach({ $0.removeFromSuperview() })
        setAspectRatio(nil)
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
        setAspectRatio(nil)

        let deckView = ReferenceDeckView(frame: self.frame)
        deckView.update(for: sharedDeckCard)
        deckView.frame = self.bounds
        deckView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceView.addSubview(deckView)
        self.hideIndicatorView()
    }

    func update(for references: [String: [String: AnyObject]]?, and url: String) {
        referenceView.subviews.forEach({ $0.removeFromSuperview() })

        // Every kind but the GIF fills the width; that branch asks for its own shape again below
        setAspectRatio(nil)

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
        } else if richObjectType == "integration_github_code_permalink",
                  let reference = firstReference["richObject"] as? [String: AnyObject] {

            let githubPermalinkView = ReferenceGithubPermalinkView(frame: self.frame)
            githubPermalinkView.update(for: reference, and: url)
            githubPermalinkView.frame = self.bounds
            githubPermalinkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            referenceView.addSubview(githubPermalinkView)
            foundReferenceView = true
        } else if richObjectType == "integration_zammad",
                  let reference = firstReference["richObject"] as? [String: AnyObject] {

            let zammadView = ReferenceZammadView(frame: self.frame)
            zammadView.update(for: reference, and: url)
            zammadView.frame = self.bounds
            zammadView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            referenceView.addSubview(zammadView)
            foundReferenceView = true
        } else if richObjectType == "deck-card",
                  let reference = firstReference["richObject"] as? [String: AnyObject] {

            let deckView = ReferenceDeckView(frame: self.frame)
            deckView.update(for: reference, and: url)
            deckView.frame = self.bounds
            deckView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            referenceView.addSubview(deckView)
            foundReferenceView = true
        } else if richObjectType == "call",
                  let reference = firstReference["richObject"] as? [String: AnyObject],
                  let openGraph = firstReference["openGraphObject"] as? [String: String?] {

            let talkView = ReferenceTalkView(frame: self.frame)
            talkView.update(for: reference, and: openGraph, and: url)
            talkView.frame = self.bounds
            talkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            referenceView.addSubview(talkView)
            foundReferenceView = true
        } else if richObjectType == "integration_giphy_gif",
                  let reference = firstReference["richObject"] as? [String: AnyObject] {

            let giphyView = ReferenceGiphyView(frame: self.frame)

            // Set before updating, as that already reports the aspect ratio the reference claims
            giphyView.aspectRatioHandler = { [weak self] aspectRatio in
                self?.setAspectRatio(aspectRatio)
            }

            giphyView.update(for: reference, and: url)
            giphyView.frame = self.bounds
            giphyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            referenceView.addSubview(giphyView)
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
