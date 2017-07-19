//
//  SearchTableViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 18.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "ContactsTableViewCell.h"

@interface SearchTableViewController : UITableViewController

@property (nonatomic, strong) NSArray *filteredContacts;

@end
