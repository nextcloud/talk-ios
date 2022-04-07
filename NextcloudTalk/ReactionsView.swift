/**
 * @copyright Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import UIKit
import AudioToolbox

@objc protocol ReactionsViewDelegate {
    func didSelectReaction(reaction: String)
    func wantsToDisplayReactionsSummary()
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
        // Configure long press gesture
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delaysTouchesBegan = true
        self.addGestureRecognizer(longPressGesture)
    }

    func handleLongPress(gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began {
            // 'Pop' feedback (strong boom)
            AudioServicesPlaySystemSound(1520)
            self.reactionsDelegate?.wantsToDisplayReactionsSummary()
       }
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
        return 2
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
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
        self.reactionsDelegate?.didSelectReaction(reaction: reactions[indexPath.row].reaction)
    }
}
