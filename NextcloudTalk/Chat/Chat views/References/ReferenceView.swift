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

    /// The GIF whose load the indicator is waiting on. A load can outlive the card that started it – by
    /// then the cell may be showing another message – so its reports are matched against this first.
    private weak var currentGiphyView: ReferenceGiphyView?

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

        // The nib holds this at a fixed inset from the leading edge, which only ever looked centred
        // because the card was full width whenever it showed. A GIF keeps it up at its own aspect ratio,
        // where that inset puts it off to one side and past the clipping bounds.
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            activityIndicatorView.widthAnchor.constraint(equalToConstant: activityIndicator.frame.width),
            activityIndicatorView.heightAnchor.constraint(equalToConstant: activityIndicator.frame.height)
        ])

        layer.cornerRadius = 8.0
        layer.masksToBounds = true

        backgroundColor = ReferenceView.backgroundFill

        self.addSubview(contentView)
    }

    func prepareForReuse() {
        referenceView.subviews.forEach({ $0.removeFromSuperview() })
        currentGiphyView = nil
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
        currentGiphyView = nil
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
        currentGiphyView = nil

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
        var deferredIndicator = false

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
            self.currentGiphyView = giphyView

            // The GIF still has to load, so this branch owns the indicator from here on
            deferredIndicator = true

            // Both are set before updating, as that already reports the aspect ratio the reference claims,
            // and a cached GIF reports its load from inside that call too
            giphyView.aspectRatioHandler = { [weak self, weak giphyView] aspectRatio in
                guard let self, let giphyView, giphyView === self.currentGiphyView else { return }

                self.setAspectRatio(aspectRatio)
            }

            giphyView.loadCompletionHandler = { [weak self, weak giphyView] in
                guard let self, let giphyView, giphyView === self.currentGiphyView else { return }

                self.hideIndicatorView()
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

        if !deferredIndicator {
            hideIndicatorView()
        }
    }
}
