/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import "TalkCapabilities.h"

NS_ASSUME_NONNULL_BEGIN

@interface ServerCapabilities : TalkCapabilities

@property NSString *accountId;
@property NSString *name;
@property NSString *slogan;
@property NSString *url;
@property NSString *logo;
@property NSString *color;
@property NSString *colorElement;
@property NSString *colorElementBright;
@property NSString *colorElementDark;
@property NSString *colorText;
@property NSString *background;
@property BOOL backgroundDefault;
@property BOOL backgroundPlain;
@property NSString *version;
@property NSInteger versionMajor;
@property NSInteger versionMinor;
@property NSInteger versionMicro;
@property NSString *edition;
@property BOOL userStatus;
@property BOOL userStatusSupportsBusy;
@property BOOL extendedSupport;
@property BOOL accountPropertyScopesVersion2;
@property BOOL accountPropertyScopesFederationEnabled;
@property BOOL accountPropertyScopesFederatedEnabled;
@property BOOL accountPropertyScopesPublishedEnabled;
@property NSString *externalSignalingServerVersion;
@property BOOL guestsAppEnabled;
@property BOOL referenceApiSupported;
@property BOOL modRewriteWorking;
@property BOOL absenceSupported;
@property BOOL absenceReplacementSupported;
@property RLMArray<RLMString> *notificationsCapabilities;

@end

NS_ASSUME_NONNULL_END
