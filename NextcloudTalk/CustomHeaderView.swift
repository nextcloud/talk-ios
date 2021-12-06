/**
 * @copyright Copyright (c) 2021 Aleksandra Lazarevic <aleksandra@nextcloud.com>
 *
 * @author Aleksandra Lazarevic  <aleksandra@nextcloud.com>
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

import Foundation
import UIKit

public class CustomHeaderView: UICollectionReusableView {
    
    public static let identifier = "HeaderCollectionReusableView"
    
    private let label: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .white
        return label
    }()
    
   @objc public func setConversationName(name: String) {
        self.label.text = name
    }
    
    @objc public func configure() {
        let statusBarSize = UIApplication.shared.statusBarFrame.size.height
        let screenRect: CGRect = UIScreen.main.bounds
        let screenWidth = screenRect.size.width;
        self.frame = CGRect(x: 0, y: statusBarSize, width: screenWidth, height: 50)
        label.frame = CGRect(x: 0, y: 0, width: screenWidth, height: 50)
        label.textAlignment = .center
        self.backgroundColor = .black
        addSubview(label)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        configure()
    }
}
