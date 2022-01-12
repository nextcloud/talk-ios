//
//  UserSettingsTableViewCell.swift
//  NextcloudTalk
//
//  Created by Aleksandra Lazarevic on 12.1.22..
//

import UIKit
import NCCommunication


let kUserSettingsCellIdentifier = "UserSettingsCellIdentifier"
let kUserSettingsTableCellNibName = "UserSettingsTableViewCell"

class SettingsUserTableViewCell: UITableViewCell {
    
    @IBOutlet weak var userImageView: UIImageView!
    @IBOutlet weak var userDisplayNameLabel: UILabel!
    @IBOutlet weak var userStatusImageView: UIImageView!
    @IBOutlet weak var serverAddressLabel: UILabel!


    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        self.userImageView.layer.cornerRadius = 40.0
        self.userImageView.layer.masksToBounds = true
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    

}
