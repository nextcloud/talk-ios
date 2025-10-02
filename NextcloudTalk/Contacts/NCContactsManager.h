/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

extern NSString * const NCContactsManagerContactsUpdatedNotification;
extern NSString * const NCContactsManagerContactsAccessUpdatedNotification;

@interface NCContactsManager : NSObject

+ (instancetype)sharedInstance;
- (void)requestContactsAccess:(void (^)(BOOL granted))completionHandler;
- (BOOL)isContactAccessDetermined;
- (BOOL)isContactAccessAuthorized;
- (void)searchInServerForAddressBookContacts:(BOOL)forceSync;
- (void)removeStoredContacts;

@end

