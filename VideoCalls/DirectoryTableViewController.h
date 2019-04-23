//
//  DirectoryTableViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DirectoryTableViewController : UITableViewController

- (instancetype)initWithPath:(NSString *)path inRoom:(NSString *)token;

@end

NS_ASSUME_NONNULL_END
