/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "VoiceMessageRecordingView.h"

@interface VoiceMessageRecordingView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (weak, nonatomic) IBOutlet UIView *leftBackgroundView;
@property (weak, nonatomic) NSTimer *labelTimer;
@property (assign, nonatomic) NSInteger startTimestamp;

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

        [self startTimeLabelTimer];

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

- (void)startTimeLabelTimer
{
    [self.recordingTimeLabel setText:@"00:00"];
    self.startTimestamp = [[NSDate date] timeIntervalSince1970];
    self.labelTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(updateTimeLabel) userInfo:nil repeats:YES];

}

- (void)stopTimeLabelTimer
{
    [self.labelTimer invalidate];
}

- (NSInteger)getTimeCounted
{
    NSInteger currentTimestamp = [[NSDate date] timeIntervalSince1970];
    return currentTimestamp - self.startTimestamp;
}

- (void)updateTimeLabel
{
    NSInteger duration = [self getTimeCounted];

    NSInteger minutes = duration / 60;
    NSInteger seconds = duration % 60;

    NSString *labelText = [NSString stringWithFormat:@"%02ld:%02ld", minutes, seconds];
    [self.recordingTimeLabel setText: labelText];
}

@end
