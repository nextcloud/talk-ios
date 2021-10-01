/**
 * @copyright Copyright (c) 2020 Marcel Müller <marcel-mueller@gmx.de>
 *
 * @author Marcel Müller <marcel-mueller@gmx.de>
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

#import <Speech/Speech.h>

#import "VoiceMessageTranscribeViewController.h"
#import "NCAppBranding.h"

@interface VoiceMessageTranscribeViewController () {
    UIActivityIndicatorView *_activityIndicator;
    NSURL *_audioFileUrl;
    NSArray *_supportedLocales;
}

@end

@implementation VoiceMessageTranscribeViewController

- (id)initWithAudiofileUrl:(NSURL *)audioFileUrl
{
    self = [super init];
    if (self) {
        self->_audioFileUrl = audioFileUrl;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"Transcript", @"TRANSLATORS transcript of a voice-message");
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [NCAppBranding themeColor];
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
    
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                      target:self action:@selector(closeViewController)];
        
        self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
        
        _activityIndicator = [[UIActivityIndicatorView alloc] init];
        _activityIndicator.color = [NCAppBranding themeTextColor];
        
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self->_activityIndicator];
        
        [_activityIndicator startAnimating];
        
        _supportedLocales = @[@"de", @"it", @"en", @"fr", @"es"];
        
        [self checkPermissionAndStartTranscription];
    }
}

- (void)closeViewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)checkPermissionAndStartTranscription API_AVAILABLE(ios(13.0))
{
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status){
        if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
            [self showSpeechRecognitionNotAvailable];
            return;
        }
        
        [self showLocaleSelection];
    }];
}

- (void)showLocaleSelection API_AVAILABLE(ios(13.0))
{
    UIAlertController *optionsActionSheet = [UIAlertController alertControllerWithTitle:nil
                                                                                message:nil
                                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Use current locale for showing localized language names
    NSLocale *currentLocale = NSLocale.currentLocale;
    
    for (NSString *localeString in _supportedLocales) {
        NSLocale *speechLocale = [[NSLocale alloc] initWithLocaleIdentifier:localeString];
        SFSpeechRecognizer *speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:speechLocale];
        
        if (!speechRecognizer.isAvailable || !speechRecognizer.supportsOnDeviceRecognition) {
            // We explicitly want to use on-device recognition
            continue;
        }
        
        UIAlertAction *localeAction = [UIAlertAction actionWithTitle:[currentLocale localizedStringForLanguageCode:localeString]
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
            [self transcribeWithLocale:speechLocale];
        }];
        
        [optionsActionSheet addAction:localeAction];
    }
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:^void (UIAlertAction *action) {
        [self closeViewController];
    }]];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)transcribeWithLocale:(NSLocale *)locale API_AVAILABLE(ios(13.0))
{
    SFSpeechRecognizer *speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    SFSpeechURLRecognitionRequest *speechRecognitionRequest = [[SFSpeechURLRecognitionRequest alloc] initWithURL:_audioFileUrl];
    speechRecognitionRequest.requiresOnDeviceRecognition = YES;
    speechRecognitionRequest.shouldReportPartialResults = YES;
    
    [speechRecognizer recognitionTaskWithRequest:speechRecognitionRequest
                                   resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error)
    {
        if (error)
        {
            NSLog(@"Recognition task failed: %@", error.description);
            return;
        }
        
        NSString *transcribedText = result.bestTranscription.formattedString;
        [self setTranscribedText:transcribedText isFinal:result.final];
    }];
    
}

- (void)showSpeechRecognitionNotAvailable
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Could not access speech recognition", nil)
                                 message:NSLocalizedString(@"Speech recognition access is not allowed. Check your settings.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setTranscribedText:(NSString *)text isFinal:(BOOL)isFinal
{
    [self.transcribeTextView setText:text];
    
    if (isFinal) {
        [_activityIndicator stopAnimating];
        [_activityIndicator removeFromSuperview];
    }
}

@end
