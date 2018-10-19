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

@property (nonatomic, strong) NSMutableDictionary *contacts;
@property (nonatomic, strong) NSArray *indexes;

- (void)setSearchResultContacts:(NSMutableDictionary *)contacts withIndexes:(NSArray *)indexes;
- (void)showSearchingUI;

@end
