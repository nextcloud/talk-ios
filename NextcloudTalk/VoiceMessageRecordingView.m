/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "VoiceMessageRecordingView.h"

@interface VoiceMessageRecordingView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (weak, nonatomic) IBOutlet UIView *leftBackgroundView;

@end

@implementation VoiceMessageRecordingView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"VoiceMessageRecordingView" owner:self options:nil];
        
        [self addSubview:self.contentView];
        
        self.contentView.frame = self.bounds;

        self.contentView.backgroundColor = [UIColor systemBackgroundColor];
        self.leftBackgroundView.backgroundColor = [UIColor systemBackgroundColor];
        
        [self.recordingTimeLabel setTimerType:MZTimerLabelTypeStopWatch];
        [self.recordingTimeLabel setTimeFormat:@"mm:ss"];
        [self.recordingTimeLabel start];
        
        [self.recordingImageView setImage:[UIImage systemImageNamed:@"mic.fill"]];
        [self.recordingImageView setTintColor:[UIColor systemRedColor]];
        [self.recordingImageView setContentMode:UIViewContentModeScaleAspectFit];
        [UIImageView animateWithDuration:0.5
                                   delay:0
                                 options:(UIViewAnimationOptionRepeat | UIViewAnimationOptionAutoreverse)
                              animations:^{self.recordingImageView.alpha = 0;}
                              completion:nil];
        
        NSString *swipeToCancelString = NSLocalizedString(@"Slide to cancel", nil);
        self.slideToCancelHintLabel.text = [NSString stringWithFormat:@"<< %@", swipeToCancelString];
    }
    
    return self;
}

@end
