/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VoiceMessageRecordingView : UIView

@property (weak, nonatomic) IBOutlet UIImageView *recordingImageView;
@property (weak, nonatomic) IBOutlet UILabel *slideToCancelHintLabel;
@property (weak, nonatomic) IBOutlet UILabel *recordingTimeLabel;

- (void)stopTimeLabelTimer;
- (NSInteger)getTimeCounted;

@end

NS_ASSUME_NONNULL_END
