//
//  SettingsViewController.swift
//  NextcloudTalk
//
//  Created by Aleksandra Lazarevic on 12.1.22..
//

import UIKit
import NCCommunication

enum SettingsSection: Int {
    case kSettingsSectionUser
    case kSettingsSectionUserStatus
    case kSettingsSectionAccounts
    case kSettingsSectionConfiguration
    case kSettingsSectionLock
    case kSettingsSectionAbout
}

enum LockSection: Int {
    case kLockSectionOn
    case kLockSectionUseSimply
    case kLockSectionNumber
}

enum ConfigurationSectionOption: Int {
    case kConfigurationSectionOptionVideo
    case kConfigurationSectionOptionBrowser
    case kConfigurationSectionOptionReadStatus
    case kConfigurationSectionOptionContactsSync
}

enum AboutSection: Int {
    case kAboutSectionPrivacy
    case kAboutSectionSourceCode
    case kAboutSectionNumber
}

class SettingsTableViewController: UITableViewController {

    @IBOutlet weak var cancelButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationItem.title = NSLocalizedString("Settings", comment: "")
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor : NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeColor()
        self.tabBarController?.tabBar.tintColor = NCAppBranding.themeColor()
        self.cancelButton.tintColor = NCAppBranding.themeTextColor()
        
        if #available(iOS 13.0, *) {
            let themeColor: UIColor = NCAppBranding.themeColor()
            let themeTextColor: UIColor = NCAppBranding.themeTextColor()
            
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.titleTextAttributes = [.foregroundColor: themeTextColor]
            appearance.backgroundColor = themeColor
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.compactAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = appearance
        }
                
        tableView.register(UINib(nibName: kUserSettingsTableCellNibName, bundle: nil), forCellReuseIdentifier: kUserSettingsCellIdentifier)
        
        //register account cell

    }
    
    func getSettingsSections() -> [Any] {
        var sections = [Any]()
        
        //Active user sections
        sections.append(SettingsSection.kSettingsSectionUser.rawValue)
        //User Status section
        let activeAccount: TalkAccount = NCDatabaseManager.sharedInstance().activeAccount()
        let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: activeAccount.accountId)
        
        if serverCapabilities.userStatus {
            sections.append(SettingsSection.kSettingsSectionUserStatus.rawValue)
        }
        //Accounts section
        if NCDatabaseManager.sharedInstance().inactiveAccounts().count > 0 {
            sections.append(SettingsSection.kSettingsSectionAccounts.rawValue)
        }
        //Configuration section
        sections.append(SettingsSection.kSettingsSectionConfiguration.rawValue)
        //About section
        sections.append(SettingsSection.kSettingsSectionAbout.rawValue)
        return sections
    }
    
    @IBAction func cancelButtonPressed(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return getSettingsSections().count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sections = getSettingsSections()
        let settingsSection = sections[section] as! Int
        
        switch (settingsSection) {
        case SettingsSection.kSettingsSectionAbout.rawValue:
            return AboutSection.kAboutSectionNumber.rawValue
        default:
            break
        }
        return 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let sections = getSettingsSections()
        
        let settingsSection = sections[indexPath.section] as! Int
            
        let cell = UITableViewCell(style: .default, reuseIdentifier: "userStatusCellIdentifier")
        
        if (settingsSection == SettingsSection.kSettingsSectionAbout.rawValue) {
            switch (indexPath.row) {
            case AboutSection.kAboutSectionPrivacy.rawValue:
                cell.textLabel!.text = NSLocalizedString("Privacy", comment: "")
                cell.imageView!.image = UIImage(named: "privacy")
            case AboutSection.kAboutSectionSourceCode.rawValue:
                cell.textLabel!.text = NSLocalizedString("Get source code", comment: "")
                cell.imageView!.image = UIImage(named: "github")
            default:
                break
            }
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let sections = getSettingsSections()
        let settignsSection = sections[section] as! Int
        
        switch (settignsSection) {
        case SettingsSection.kSettingsSectionAbout.rawValue:
            return NSLocalizedString("About", comment: "")
        default:
            break
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let sections = getSettingsSections()
        let settignsSection = sections[section] as! Int
        
        if (settignsSection == SettingsSection.kSettingsSectionAbout.rawValue) {
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
            return appName + appVersion + copyright
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let sections = getSettingsSections()
        let currentSection = sections[indexPath.section] as! Int
        if (currentSection == SettingsSection.kSettingsSectionUser.rawValue) {
            return 100;
        }
        return 48;
    }

}
