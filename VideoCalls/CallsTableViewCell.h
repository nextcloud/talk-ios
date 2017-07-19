//
//  CallsTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 19.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const kCallCellIdentifier;
extern NSString *const kCallsTableCellNibName;

@interface CallsTableViewCell : UITableViewCell

@property(nonatomic, weak) IBOutlet UIImageView *callImage;
@property(nonatomic, weak) IBOutlet UILabel *labelTitle;

@end
