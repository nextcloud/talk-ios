/**
 * @copyright Copyright (c) 2021 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
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

#import <UIKit/UIKit.h>

@interface DetailedOption : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) UIImage *image;
@property (nonatomic, assign) BOOL selected;
@end

typedef enum DetailedOptionsSelectorType {
    DetailedOptionsSelectorTypeDefault = 0,
    DetailedOptionsSelectorTypeAccounts
} DetailedOptionsSelectorType;

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

- (instancetype)initWithOptions:(NSArray *)options forSenderIdentifier:(NSString *)senderId;
- (instancetype)initWithAccounts:(NSArray *)accounts;

@end

