/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
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

    [NCAppBranding styleViewController:self];

    self.navigationItem.title = NSLocalizedString(@"Transcript", @"TRANSLATORS transcript of a voice-message");

    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                  target:self action:@selector(closeViewController)];
    
    self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    
    _activityIndicator = [[UIActivityIndicatorView alloc] init];
    if (@available(iOS 26.0, *)) {
        _activityIndicator.color = [UIColor labelColor];
    } else {
        _activityIndicator.color = [NCAppBranding themeTextColor];
    }
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self->_activityIndicator];
    
    [_activityIndicator startAnimating];
    
    _supportedLocales = @[@"de", @"it", @"en", @"fr", @"es"];
    
    [self checkPermissionAndStartTranscription];
}

- (void)closeViewController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)checkPermissionAndStartTranscription
{
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status){
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
                [self showSpeechRecognitionNotAvailable];
                return;
            }
            
            [self showLocaleSelection];
        });
    }];
}

- (void)showLocaleSelection
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

- (void)transcribeWithLocale:(NSLocale *)locale
{
    SFSpeechRecognizer *speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    SFSpeechURLRecognitionRequest *speechRecognitionRequest = [[SFSpeechURLRecognitionRequest alloc] initWithURL:_audioFileUrl];
    speechRecognitionRequest.requiresOnDeviceRecognition = YES;
    speechRecognitionRequest.shouldReportPartialResults = YES;
    
    [speechRecognizer recognitionTaskWithRequest:speechRecognitionRequest
                                   resultHandler:^(SFSpeechRecognitionResult * _Nullable result, NSError * _Nullable error)
    {
        if (error) {
            NSLog(@"Recognition task failed: %@", error.description);
            [self showSpeechRecognitionError:error.localizedDescription];
            return;
        }
        
        NSString *transcribedText = result.bestTranscription.formattedString;
        [self setTranscribedText:transcribedText isFinal:result.final];
    }];
    
}

- (void)showSpeechRecognitionError:(NSString *)errorDescription
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Speech recognition failed", nil)
                                 message:errorDescription
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction * _Nonnull action) {
        [self closeViewController];
    }];
    
    [alert addAction:okButton];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showSpeechRecognitionNotAvailable
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Could not access speech recognition", nil)
                                 message:NSLocalizedString(@"Speech recognition access is not allowed. Check your settings.", nil)
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* settingsButton = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", nil)
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
        [self closeViewController];
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }];
    [alert addAction:settingsButton];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self closeViewController];
    }]];
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
