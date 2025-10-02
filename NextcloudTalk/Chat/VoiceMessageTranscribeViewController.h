/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VoiceMessageTranscribeViewController : UIViewController

@property (weak, nonatomic) IBOutlet UITextView *transcribeTextView;

- (id)initWithAudiofileUrl:(NSURL *)audioFileUrl;

@end

NS_ASSUME_NONNULL_END
