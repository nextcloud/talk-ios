/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DirectoryTableViewController : UITableViewController

- (instancetype)initWithPath:(NSString *)path inRoom:(NSString *)token andThread:(NSInteger)threadId;

@end

NS_ASSUME_NONNULL_END
