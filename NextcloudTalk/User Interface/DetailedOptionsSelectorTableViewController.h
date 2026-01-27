/**
 * SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import "NCTypes.h"

@interface DetailedOption : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) UIImage *image;
@property (nonatomic, assign) BOOL selected;
@end


@class DetailedOptionsSelectorTableViewController;
@protocol DetailedOptionsSelectorTableViewControllerDelegate <NSObject>
- (void)detailedOptionsSelector:(DetailedOptionsSelectorTableViewController *)viewController didSelectOptionWithIdentifier:(DetailedOption *)option;
- (void)detailedOptionsSelectorWasCancelled:(DetailedOptionsSelectorTableViewController *)viewController;
@end

@interface DetailedOptionsSelectorTableViewController : UITableViewController

@property (nonatomic, weak) id<DetailedOptionsSelectorTableViewControllerDelegate> delegate;
@property (nonatomic, strong) NSArray *options;
@property (nonatomic, strong) NSString *senderId;
@property (nonatomic, assign) DetailedOptionsSelectorType type;

- (instancetype)initWithOptions:(NSArray *)options forSenderIdentifier:(NSString *)senderId andStyle:(UITableViewStyle)style;
- (instancetype)initWithAccounts:(NSArray *)accounts andStyle:(UITableViewStyle)style;

@end

