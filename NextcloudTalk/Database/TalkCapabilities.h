/**
 * SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Realm/Realm.h>

NS_ASSUME_NONNULL_BEGIN

@interface TalkCapabilities : RLMObject

@property RLMArray<RLMString> *talkCapabilities;
@property NSInteger chatMaxLength;
@property NSString *translations;
@property BOOL hasTranslationProviders;
@property BOOL canCreate;
@property BOOL attachmentsAllowed;
@property NSString *attachmentsFolder;
@property BOOL readStatusPrivacy;
@property BOOL typingPrivacy;
@property BOOL callEnabled;
@property RLMArray<RLMString> *callReactions;
@property NSString *talkVersion;
@property BOOL recordingEnabled;
@property BOOL federationEnabled;
@property BOOL federationIncomingEnabled;
@property BOOL federationOutgoingEnabled;
@property BOOL federationOnlyTrustedServers;
@property NSInteger maxGifSize;
@property NSInteger summaryThreshold;
@property NSInteger descriptionLength;
@property NSInteger retentionEvent;
@property NSInteger retentionPhone;
@property NSInteger retentionInstantMeetings;

@end

NS_ASSUME_NONNULL_END
