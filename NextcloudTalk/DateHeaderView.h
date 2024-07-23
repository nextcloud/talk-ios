/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

static CGFloat kDateHeaderViewHeight = 34.0;

@interface DateHeaderView : UIView

@property (weak, nonatomic) IBOutlet UILabel *dateLabel;

@end
