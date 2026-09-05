//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objc protocol ReactionsViewDelegate {
    func didSelectReaction(reaction: NCChatReaction)
}

@objcMembers class ReactionsView: UICollectionView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    public weak var reactionsDelegate: ReactionsViewDelegate?
    var reactions: [NCChatReaction] = []

    /// Spacing between two reactions
    private static let itemSpacing: CGFloat = 8

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    /// Tracks the touch start time to differentiate quick taps from long presses
    private var touchBeganTime: Date?

    /// Maximum duration (in seconds) for a touch to be considered a tap vs long press
    private let maxTapDuration: TimeInterval = 0.25

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setupReactionView()
    }

    required override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: layout)
        self.setupReactionView()
    }

    func setupReactionView() {
        self.dataSource = self
        self.delegate = self
        self.register(UINib(nibName: "ReactionsViewCell", bundle: .main), forCellWithReuseIdentifier: "ReactionCellIdentifier")
        self.backgroundColor = .clear
        self.showsHorizontalScrollIndicator = false
    }

    // MARK: - Touch tracking

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchBeganTime = Date()
        feedbackGenerator.prepare()
        super.touchesBegan(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchBeganTime = nil
        super.touchesCancelled(touches, with: event)
    }

    func updateReactions(reactions: [NCChatReaction]) {
        self.reactions = reactions
        self.reloadData()

        // Cells keep their ReactionsView across reuse, so without this it stays at the width of the
        // reactions it showed before and silently clips the new ones
        self.invalidateIntrinsicContentSize()

        // A reused view might still be scrolled to where the previous message's reactions were
        self.setContentOffset(.zero, animated: false)
    }

    // MARK: - Scroll fade

    override func layoutSubviews() {
        super.layoutSubviews()

        // Also called while scrolling, so the fade follows the content offset
        self.updateHorizontalScrollFade()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return reactions.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfSections section: Int) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return ReactionsView.itemSpacing
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return ReactionsView.itemSpacing
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if indexPath.row < reactions.count {
            return ReactionsViewCell.sizeForReaction(reaction: reactions[indexPath.row])
        }
        return CGSize(width: 50, height: 30)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ReactionCellIdentifier", for: indexPath) as? ReactionsViewCell
        if indexPath.row < reactions.count {
            cell?.setReaction(reaction: reactions[indexPath.row])
        }
        return cell ?? UICollectionViewCell()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // Only trigger reaction toggle for quick taps (not long presses intended to show "who reacted")
        if let touchBeganTime = touchBeganTime {
            let touchDuration = Date().timeIntervalSince(touchBeganTime)
            self.touchBeganTime = nil

            // If the touch was too long, it was likely intended as a long press - ignore it
            guard touchDuration <= maxTapDuration else {
                return
            }
        }

        if indexPath.row < reactions.count {
            self.feedbackGenerator.impactOccurred()
            self.reactionsDelegate?.didSelectReaction(reaction: reactions[indexPath.row])
        }
    }

    override var intrinsicContentSize: CGSize {
        // Not collectionViewContentSize: the flow layout only recomputes that while laying out, so right
        // after reloadData() it still reports the width of the previous reactions
        let width = self.reactions.reduce(0) { $0 + ReactionsViewCell.sizeForReaction(reaction: $1).width }
            + CGFloat(max(self.reactions.count - 1, 0)) * ReactionsView.itemSpacing

        return .init(width: width, height: UICollectionView.noIntrinsicMetric)
    }
}
