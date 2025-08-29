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

    func updateReactions(reactions: [NCChatReaction]) {
        self.reactions = reactions
        self.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return reactions.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfSections section: Int) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 8
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 8
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if indexPath.row < reactions.count {
            return ReactionsViewCell().sizeForReaction(reaction: reactions[indexPath.row])
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
        if indexPath.row < reactions.count {
            self.reactionsDelegate?.didSelectReaction(reaction: reactions[indexPath.row])
        }
    }

    override var intrinsicContentSize: CGSize {
        return .init(width: self.collectionViewLayout.collectionViewContentSize.width, height: UICollectionView.noIntrinsicMetric)
    }
}
