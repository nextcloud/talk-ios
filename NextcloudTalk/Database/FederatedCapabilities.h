/**
 * SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import "TalkCapabilities.h"

NS_ASSUME_NONNULL_BEGIN

@interface FederatedCapabilities : TalkCapabilities

@property NSString *internalId; // {accountId}@{remoteServer}@{roomToken}
@property NSString *accountId;
@property NSString *remoteServer;
@property NSString *roomToken;

@end

NS_ASSUME_NONNULL_END
