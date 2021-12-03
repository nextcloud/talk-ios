//
//  CustomHeaderView.swift
//  NextcloudTalk
//
//  Created by Aleksandra Lazarevic on 30.11.21..
//

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
