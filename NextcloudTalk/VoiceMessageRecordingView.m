/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
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
        
        [self.recordingImageView setImage:[[UIImage imageNamed:@"audio"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
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
