//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

// Verifies that NCDatabaseManager parses a `ocs/v1.php/cloud/capabilities` response into
// ServerCapabilities/TalkCapabilities and that the parsed features can be queried again.
//
// The fixtures are deliberately parsed with JSONSerialization instead of being written as Swift
// dictionary literals, so that the values have the same runtime types as in production: NSNumber
// for booleans/numbers and NSNull for `null`. This is what makes the `as? NSNumber` casts in
// NCDatabaseManager meaningful to test.
final class UnitServerCapabilities: TestBaseRealm {

    private var databaseManager: NCDatabaseManager { NCDatabaseManager.sharedInstance() }
    private var accountId: String { TestBaseRealm.fakeAccountId }

    // MARK: - Helpers

    private func dataDict(from json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ocs = try XCTUnwrap(root["ocs"] as? [String: Any])
        return try XCTUnwrap(ocs["data"] as? [String: Any])
    }

    private func storeCapabilities(from json: String) throws -> ServerCapabilities {
        let data = try dataDict(from: json)
        databaseManager.setServerCapabilities(data, forAccountId: accountId)
        return try XCTUnwrap(databaseManager.serverCapabilities(forAccountId: accountId))
    }

    // MARK: - Full response of a real server

    func testParsingServerCapabilities() throws {
        let capabilities = try storeCapabilities(from: Self.capabilitiesResponse)

        XCTAssertEqual(capabilities.accountId, accountId)

        // theming
        XCTAssertEqual(capabilities.name, "ABCD")
        XCTAssertEqual(capabilities.slogan, "ein sicherer Ort für all Ihre Daten")
        XCTAssertEqual(capabilities.url, "https://nextcloud.com")
        XCTAssertEqual(capabilities.logo, "https://nextcloud-mm.local/core/img/logo/logo.svg?v=1")
        XCTAssertEqual(capabilities.color, "#00679e")
        XCTAssertEqual(capabilities.colorElement, "#00679e")
        XCTAssertEqual(capabilities.colorElementBright, "#00679e")
        XCTAssertEqual(capabilities.colorElementDark, "#00679e")
        XCTAssertEqual(capabilities.colorText, "#ffffff")
        XCTAssertEqual(capabilities.background, "https://nextcloud-mm.local/apps/theming/img/background/jo-myoung-hee-fluid.webp")
        XCTAssertTrue(capabilities.backgroundDefault)
        XCTAssertFalse(capabilities.backgroundPlain)

        // version
        XCTAssertEqual(capabilities.version, "35.0.0 dev")
        XCTAssertEqual(capabilities.versionMajor, 35)
        XCTAssertEqual(capabilities.versionMinor, 0)
        XCTAssertEqual(capabilities.versionMicro, 0)
        XCTAssertEqual(capabilities.edition, "")
        XCTAssertFalse(capabilities.extendedSupport)

        // user_status
        XCTAssertTrue(capabilities.userStatus)
        XCTAssertTrue(capabilities.userStatusSupportsBusy)

        // provisioning_api
        XCTAssertTrue(capabilities.accountPropertyScopesVersion2)
        XCTAssertTrue(capabilities.accountPropertyScopesFederatedEnabled)
        XCTAssertFalse(capabilities.accountPropertyScopesPublishedEnabled)
        // The server does not report "AccountPropertyScopesFederationEnabled" at all
        XCTAssertFalse(capabilities.accountPropertyScopesFederationEnabled)

        // guests, core, dav
        XCTAssertTrue(capabilities.guestsAppEnabled)
        XCTAssertTrue(capabilities.referenceApiSupported)
        XCTAssertFalse(capabilities.modRewriteWorking)
        XCTAssertTrue(capabilities.absenceSupported)
        XCTAssertTrue(capabilities.absenceReplacementSupported)

        // password_policy: this response has no "policies.sharing", so the top level value is used
        XCTAssertEqual(capabilities.passwordPolicyGenerateAPIEndpoint, "https://nextcloud-mm.local/ocs/v2.php/apps/password_policy/api/v1/generate")
        XCTAssertEqual(capabilities.passwordPolicyValidateAPIEndpoint, "https://nextcloud-mm.local/ocs/v2.php/apps/password_policy/api/v1/validate")
        XCTAssertEqual(capabilities.passwordPolicyMinLength, 10)

        // notifications
        XCTAssertTrue(databaseManager.serverHasNotificationsCapability(.exists, forAccountId: accountId))
        XCTAssertTrue(databaseManager.serverHasNotificationsCapability(.testPush, forAccountId: accountId))
        XCTAssertFalse(databaseManager.serverHasNotificationsCapability("not-a-notifications-capability", forAccountId: accountId))
    }

    func testParsingTalkCapabilities() throws {
        let capabilities = try storeCapabilities(from: Self.capabilitiesResponse)

        XCTAssertEqual(capabilities.talkVersion, "25.0.0-dev.0")

        // attachments
        XCTAssertTrue(capabilities.attachmentsAllowed)
        XCTAssertEqual(capabilities.attachmentsFolder, "/Talk")
        XCTAssertTrue(capabilities.conversationSubfoldersEnabled)

        // call
        XCTAssertTrue(capabilities.callEnabled)
        XCTAssertFalse(capabilities.recordingEnabled)
        XCTAssertFalse(capabilities.e2eeCallsEnabled)
        XCTAssertEqual(capabilities.callReactions.count, 12)
        XCTAssertEqual(capabilities.callReactions.value(forKey: "self") as? [String], ["❤️", "🎉", "👏", "👋", "👍", "👎", "🔥", "😂", "🤩", "🤔", "😲", "😥"])

        // conversations
        XCTAssertTrue(capabilities.canCreate)
        XCTAssertEqual(capabilities.descriptionLength, 2000)
        XCTAssertEqual(capabilities.retentionEvent, 28)
        XCTAssertEqual(capabilities.retentionPhone, 7)
        XCTAssertEqual(capabilities.retentionInstantMeetings, 1)
        XCTAssertEqual(capabilities.roomsSortOrder, NCRoomSortOrder.activity.rawValue)
        XCTAssertEqual(capabilities.roomsGroupMode, NCRoomGroupMode.none.rawValue)

        // chat: "read-privacy" and "typing-privacy" are integers (0/1) on the wire
        XCTAssertFalse(capabilities.readStatusPrivacy)
        XCTAssertFalse(capabilities.typingPrivacy)
        XCTAssertEqual(capabilities.chatMaxLength, 32000)
        XCTAssertEqual(capabilities.summaryThreshold, 100)
        XCTAssertFalse(capabilities.hasTranslationProviders)
        // No "translations" key in this response, so nothing is stored
        XCTAssertTrue(capabilities.translations.isEmpty)

        // federation
        XCTAssertTrue(capabilities.federationEnabled)
        XCTAssertTrue(capabilities.federationIncomingEnabled)
        XCTAssertTrue(capabilities.federationOutgoingEnabled)
        XCTAssertFalse(capabilities.federationOnlyTrustedServers)
        XCTAssertTrue(databaseManager.serverCanInviteFederatedUsersforAccountId(accountId))

        // previews
        XCTAssertEqual(capabilities.maxGifSize, 3145728)
    }

    // Every feature the server advertises has to be readable again through the public API. This
    // covers the `setValue(_:forKey: "talkCapabilities")` / `value(forKey: "self")` round trip of
    // the RLMArray<RLMString> property.
    func testAllAdvertisedFeaturesAreStored() throws {
        let capabilities = try storeCapabilities(from: Self.capabilitiesResponse)

        let data = try dataDict(from: Self.capabilitiesResponse)
        let spreed = try XCTUnwrap((data["capabilities"] as? [String: Any])?["spreed"] as? [String: Any])
        let features = try XCTUnwrap(spreed["features"] as? [String])

        XCTAssertFalse(features.isEmpty)
        XCTAssertEqual(Int(capabilities.talkCapabilities.count), features.count)

        for feature in features {
            XCTAssertTrue(databaseManager.serverHasTalkCapability(feature, forAccountId: accountId), "Missing feature: \(feature)")
        }

        XCTAssertFalse(databaseManager.serverHasTalkCapability("not-a-talk-capability", forAccountId: accountId))
    }

    func testTypedCapabilityChecks() throws {
        _ = try storeCapabilities(from: Self.capabilitiesResponse)

        let advertised: [TalkCapability] = [
            .conversationV4, .threads, .pinnedMessages, .conversationTags, .reactions, .messageExpiration,
            .banV1, .federationV1, .federationV2, .scheduleMessages, .importantConversations,
            .sensitiveConversations, .talkPollsDrafts, .editDraftPoll, .forceMute, .botV1, .reactPermission,
            .chatReferenceId, .conversationCreationAll, .callNotificationState, .scheduleMeeting
        ]

        for capability in advertised {
            XCTAssertTrue(databaseManager.serverHasTalkCapability(capability, forAccountId: accountId), "Missing capability: \(capability.rawValue)")
        }

        // "chat-summary-api" is only listed in "features-local" on this server, because the summary
        // is added to "features" only when the server actually has a task processing provider.
        // We only read "features", so the capability has to be reported as unsupported.
        XCTAssertFalse(databaseManager.serverHasTalkCapability(.chatSummary, forAccountId: accountId))
    }

    // MARK: - Missing values

    // A server that reports "spreed" without any config must end up with the documented defaults
    // instead of zero/false everywhere.
    func testDefaultsForMissingTalkConfig() throws {
        let capabilities = try storeCapabilities(from: #"""
        {
          "ocs": {
            "data": {
              "capabilities": {
                "spreed": {
                  "features": [
                    "conversation-v4"
                  ],
                  "config": {}
                }
              }
            }
          }
        }
        """#)

        XCTAssertTrue(capabilities.callEnabled)
        XCTAssertTrue(capabilities.canCreate)
        XCTAssertTrue(capabilities.typingPrivacy)
        XCTAssertEqual(capabilities.descriptionLength, 500)
        XCTAssertEqual(capabilities.roomsSortOrder, NCRoomSortOrder.unsupported.rawValue)
        XCTAssertEqual(capabilities.roomsGroupMode, NCRoomGroupMode.unsupported.rawValue)

        XCTAssertFalse(capabilities.recordingEnabled)
        XCTAssertFalse(capabilities.e2eeCallsEnabled)
        XCTAssertFalse(capabilities.attachmentsAllowed)
        XCTAssertFalse(capabilities.conversationSubfoldersEnabled)
        XCTAssertFalse(capabilities.readStatusPrivacy)
        XCTAssertFalse(capabilities.hasTranslationProviders)
        XCTAssertFalse(capabilities.federationEnabled)
        XCTAssertFalse(capabilities.federationIncomingEnabled)
        XCTAssertFalse(capabilities.federationOutgoingEnabled)
        XCTAssertFalse(capabilities.federationOnlyTrustedServers)
        XCTAssertEqual(capabilities.chatMaxLength, 0)
        XCTAssertEqual(capabilities.summaryThreshold, 0)
        XCTAssertEqual(capabilities.maxGifSize, 0)
        XCTAssertEqual(capabilities.callReactions.count, 0)

        XCTAssertTrue(databaseManager.serverHasTalkCapability(.conversationV4, forAccountId: accountId))
        XCTAssertFalse(databaseManager.serverHasTalkCapability(.threads, forAccountId: accountId))
    }

    // An account without any stored capabilities must not report any capability as supported.
    func testNoStoredCapabilities() {
        XCTAssertNil(databaseManager.serverCapabilities(forAccountId: accountId))
        XCTAssertFalse(databaseManager.serverHasTalkCapability(.conversationV4, forAccountId: accountId))
        XCTAssertFalse(databaseManager.serverHasNotificationsCapability(.exists, forAccountId: accountId))
        XCTAssertFalse(databaseManager.serverCanInviteFederatedUsersforAccountId(accountId))
    }

    // `null` values are NSNull once decoded. They must fall back to the defaults instead of being
    // treated as `false`/`0`.
    func testNullValuesFallBackToDefaults() throws {
        let capabilities = try storeCapabilities(from: #"""
        {
          "ocs": {
            "data": {
              "version": {
                "major": null,
                "string": null
              },
              "capabilities": {
                "theming": {
                  "name": null
                },
                "spreed": {
                  "features": [
                    "conversation-v4"
                  ],
                  "version": null,
                  "config": {
                    "call": {
                      "enabled": null,
                      "recording": null,
                      "end-to-end-encryption": null
                    },
                    "conversations": {
                      "can-create": null,
                      "description-length": null,
                      "sort-order": null,
                      "group-mode": null,
                      "retention-event": null
                    },
                    "chat": {
                      "max-length": null,
                      "read-privacy": null,
                      "typing-privacy": null,
                      "summary-threshold": null,
                      "translations": null
                    },
                    "attachments": {
                      "allowed": null,
                      "folder": null,
                      "conversation-subfolders": null
                    },
                    "federation": {
                      "enabled": null
                    },
                    "previews": {
                      "max-gif-size": null
                    }
                  }
                }
              }
            }
          }
        }
        """#)

        XCTAssertEqual(capabilities.name, "")
        XCTAssertEqual(capabilities.version, "")
        XCTAssertEqual(capabilities.versionMajor, 0)
        XCTAssertEqual(capabilities.talkVersion, "")
        XCTAssertEqual(capabilities.attachmentsFolder, "")
        XCTAssertFalse(capabilities.attachmentsAllowed)
        XCTAssertFalse(capabilities.conversationSubfoldersEnabled)
        XCTAssertFalse(capabilities.e2eeCallsEnabled)

        XCTAssertTrue(capabilities.callEnabled)
        XCTAssertTrue(capabilities.canCreate)
        XCTAssertTrue(capabilities.typingPrivacy)
        XCTAssertEqual(capabilities.descriptionLength, 500)
        XCTAssertEqual(capabilities.retentionEvent, 0)
        XCTAssertEqual(capabilities.roomsSortOrder, NCRoomSortOrder.unsupported.rawValue)
        XCTAssertEqual(capabilities.roomsGroupMode, NCRoomGroupMode.unsupported.rawValue)
        XCTAssertFalse(capabilities.recordingEnabled)
        XCTAssertFalse(capabilities.federationEnabled)
        XCTAssertEqual(capabilities.chatMaxLength, 0)
        XCTAssertEqual(capabilities.maxGifSize, 0)
        XCTAssertEqual(capabilities.callReactions.count, 0)
        XCTAssertTrue(capabilities.translations.isEmpty)
    }

    // MARK: - Values that are only read for some servers

    private struct SortOrderAndGroupMode {
        let sortOrder: String
        let groupMode: String
        let expectedSortOrder: NCRoomSortOrder
        let expectedGroupMode: NCRoomGroupMode
    }

    func testSortOrderAndGroupMode() throws {
        let json = #"""
        {
          "ocs": {
            "data": {
              "capabilities": {
                "spreed": {
                  "features": [],
                  "config": {
                    "conversations": {
                      "sort-order": "%@",
                      "group-mode": "%@"
                    }
                  }
                }
              }
            }
          }
        }
        """#

        let combinations: [SortOrderAndGroupMode] = [
            SortOrderAndGroupMode(sortOrder: "activity", groupMode: "none", expectedSortOrder: .activity, expectedGroupMode: .none),
            SortOrderAndGroupMode(sortOrder: "alphabetical", groupMode: "group-first", expectedSortOrder: .alphabetical, expectedGroupMode: .groupFirst),
            SortOrderAndGroupMode(sortOrder: "something-new", groupMode: "private-first", expectedSortOrder: .activity, expectedGroupMode: .privateFirst),
            SortOrderAndGroupMode(sortOrder: "activity", groupMode: "something-new", expectedSortOrder: .activity, expectedGroupMode: .none)
        ]

        for combination in combinations {
            let capabilities = try storeCapabilities(from: String(format: json, combination.sortOrder, combination.groupMode))
            XCTAssertEqual(capabilities.roomsSortOrder, combination.expectedSortOrder.rawValue, "sort-order: \(combination.sortOrder)")
            XCTAssertEqual(capabilities.roomsGroupMode, combination.expectedGroupMode.rawValue, "group-mode: \(combination.groupMode)")
        }
    }

    func testPasswordPolicySharingOverridesTopLevelMinLength() throws {
        let capabilities = try storeCapabilities(from: #"""
        {
          "ocs": {
            "data": {
              "capabilities": {
                "password_policy": {
                  "minLength": 10,
                  "policies": {
                    "sharing": {
                      "minLength": 15
                    }
                  }
                }
              }
            }
          }
        }
        """#)

        XCTAssertEqual(capabilities.passwordPolicyMinLength, 15)
    }

    func testTranslations() throws {
        let capabilities = try storeCapabilities(from: #"""
        {
          "ocs": {
            "data": {
              "capabilities": {
                "spreed": {
                  "features": [],
                  "config": {
                    "chat": {
                      "has-translation-providers": true,
                      "translations": [
                        {
                          "from": "de",
                          "fromLabel": "German",
                          "to": "en",
                          "toLabel": "English"
                        },
                        {
                          "from": "en",
                          "fromLabel": "English",
                          "to": "de",
                          "toLabel": "German"
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
        """#)

        XCTAssertTrue(capabilities.hasTranslationProviders)
        XCTAssertFalse(capabilities.translations.isEmpty)

        XCTAssertTrue(databaseManager.hasTranslationProviders(forAccountId: accountId))
        XCTAssertTrue(databaseManager.hasAvailableTranslations(forAccountId: accountId))

        let translations = databaseManager.availableTranslations(forAccountId: accountId)
        XCTAssertEqual(translations.count, 2)
        XCTAssertEqual(translations.first?.from, "de")
        XCTAssertEqual(translations.first?.fromLabel, "German")
        XCTAssertEqual(translations.first?.to, "en")
        XCTAssertEqual(translations.first?.toLabel, "English")
    }

    // MARK: - Federated capabilities

    func testFederatedCapabilities() throws {
        // Local capabilities without the federated features, to make sure the room does not fall
        // back to the capabilities of the local server
        _ = try storeCapabilities(from: #"""
        {
          "ocs": {
            "data": {
              "capabilities": {
                "spreed": {
                  "features": [
                    "conversation-v4"
                  ],
                  "config": {
                    "chat": {
                      "max-length": 1000
                    }
                  }
                }
              }
            }
          }
        }
        """#)

        let data = try dataDict(from: Self.capabilitiesResponse)
        let spreed = try XCTUnwrap((data["capabilities"] as? [String: Any])?["spreed"] as? [String: Any])

        let remoteServer = "https://remote.example.com"
        let roomToken = "federatedToken"

        let federatedRoom = addRoom(withToken: roomToken) { room in
            room.remoteServer = remoteServer
            room.remoteToken = roomToken
        }
        XCTAssertTrue(federatedRoom.isFederated)

        databaseManager.setFederatedCapabilities(spreed, forAccountId: accountId, remoteServer: remoteServer, roomToken: roomToken, withProxyHash: "proxyHash")

        let federatedCapabilities = try XCTUnwrap(databaseManager.federatedCapabilities(forAccountId: accountId, remoteServer: remoteServer, roomToken: roomToken))
        XCTAssertEqual(federatedCapabilities.internalId, "\(accountId)@\(remoteServer)@\(roomToken)")
        XCTAssertEqual(federatedCapabilities.talkVersion, "25.0.0-dev.0")
        XCTAssertEqual(federatedCapabilities.chatMaxLength, 32000)

        // Capabilities of the remote server are used
        XCTAssertTrue(databaseManager.roomHasTalkCapability(.threads, for: federatedRoom))
        XCTAssertTrue(databaseManager.roomHasTalkCapability(.conversationV4, for: federatedRoom))
        XCTAssertFalse(databaseManager.roomHasTalkCapability(.chatSummary, for: federatedRoom))
        XCTAssertEqual(databaseManager.roomTalkCapabilities(for: federatedRoom)?.chatMaxLength, 32000)

        // The proxy hash is stored on the room
        XCTAssertEqual(databaseManager.room(withToken: roomToken, forAccountId: accountId)?.lastReceivedProxyHash, "proxyHash")

        // A local room still uses the capabilities of the local server
        let localRoom = addRoom(withToken: "localToken")
        XCTAssertFalse(localRoom.isFederated)
        XCTAssertFalse(databaseManager.roomHasTalkCapability(.threads, for: localRoom))
        XCTAssertTrue(databaseManager.roomHasTalkCapability(.conversationV4, for: localRoom))
        XCTAssertEqual(databaseManager.roomTalkCapabilities(for: localRoom)?.chatMaxLength, 1000)
    }

    func testUnknownFederatedRoomHasNoCapabilities() throws {
        _ = try storeCapabilities(from: Self.capabilitiesResponse)

        let federatedRoom = addRoom(withToken: "unknownToken") { room in
            room.remoteServer = "https://remote.example.com"
            room.remoteToken = "unknownToken"
        }

        XCTAssertTrue(federatedRoom.isFederated)
        XCTAssertNil(databaseManager.roomTalkCapabilities(for: federatedRoom))
        XCTAssertFalse(databaseManager.roomHasTalkCapability(.threads, for: federatedRoom))
    }

    // MARK: - Fixture

    // Response of `ocs/v1.php/cloud/capabilities?format=json` of a Nextcloud 35 server with Talk 25.
    // Only the "circles", "sharing" and "files_sharing" blocks were removed, everything else is
    // unchanged, including apps that we don't read at all.
    private static let capabilitiesResponse = #"""
    {
      "ocs": {
        "meta": {
          "status": "ok",
          "statuscode": 200,
          "message": "OK"
        },
        "data": {
          "version": {
            "major": 35,
            "minor": 0,
            "micro": 0,
            "string": "35.0.0 dev",
            "edition": "",
            "extendedSupport": false
          },
          "capabilities": {
            "core": {
              "pollinterval": 60,
              "webdav-root": "remote.php/webdav",
              "reference-api": true,
              "reference-regex": "(\\s|\\n|^)(https?:\\/\\/)([-A-Z0-9+_.]+(?::[0-9]+)?(?:\\/[-A-Z0-9+&@#%?=~_|!:,.;()]*)*)(\\s|\\n|$)",
              "mod-rewrite-working": false,
              "user": {
                "language": "de_DE",
                "locale": "",
                "timezone": "Europe/Berlin"
              },
              "can-create-app-token": true
            },
            "bruteforce": {
              "delay": 800,
              "allow-listed": false
            },
            "activity": {
              "apiv2": [
                "filters",
                "filters-api",
                "previews",
                "rich-strings"
              ]
            },
            "app_api": {
              "loglevel": 1,
              "version": "35.0.0-dev.0"
            },
            "calendar": {
              "webui": true
            },
            "files": {
              "comments": true,
              "$comment": "\"blacklisted_files\" is deprecated as of Nextcloud 30, use \"forbidden_filenames\" instead",
              "blacklisted_files": [
                ".htaccess"
              ],
              "forbidden_filenames": [
                ".htaccess"
              ],
              "forbidden_filename_basenames": [],
              "forbidden_filename_characters": [
                "\\",
                "/"
              ],
              "forbidden_filename_extensions": [
                ".filepart",
                ".part"
              ],
              "bigfilechunking": true,
              "chunked_upload": {
                "max_size": 104857600,
                "max_parallel_count": 5
              },
              "file_conversions": [],
              "windows_compatible_filenames": false,
              "directEditing": {
                "url": "https://nextcloud-mm.local/ocs/v2.php/apps/files/api/v1/directEditing",
                "etag": "1dc1b8f0cb70e547508c330170656228",
                "supportsFileId": true
              },
              "locking": "1.0",
              "api-feature-lock-type": true,
              "undelete": true,
              "delete_from_trash": true,
              "versioning": true,
              "version_labeling": true,
              "version_deletion": true
            },
            "dav": {
              "chunking": "1.0",
              "public_shares_chunking": true,
              "search_supports_creation_time": true,
              "search_supports_upload_time": true,
              "search_supports_last_activity": true,
              "bulkupload": "1.0",
              "absence-supported": true,
              "absence-replacement": true
            },
            "groupfolders": {
              "appVersion": "23.0.0-dev.0",
              "hasGroupFolders": false
            },
            "guests": {
              "enabled": true
            },
            "integration_giphy": {
              "enabled": true,
              "configured": false
            },
            "notifications": {
              "ocs-endpoints": [
                "list",
                "get",
                "delete",
                "delete-all",
                "icons",
                "rich-strings",
                "action-web",
                "user-status",
                "exists",
                "test-push"
              ],
              "push": [
                "devices",
                "object-data",
                "delete"
              ],
              "admin-notifications": [
                "ocs",
                "cli"
              ]
            },
            "password_policy": {
              "api": {
                "generate": "https://nextcloud-mm.local/ocs/v2.php/apps/password_policy/api/v1/generate",
                "validate": "https://nextcloud-mm.local/ocs/v2.php/apps/password_policy/api/v1/validate"
              },
              "policies": {
                "account": {
                  "minLength": 10,
                  "enforceHaveIBeenPwned": true,
                  "enforceNonCommonPassword": true,
                  "enforceNumericCharacters": false,
                  "enforceSpecialCharacters": false,
                  "enforceUpperLowerCase": false
                }
              },
              "minLength": 10,
              "enforceNonCommonPassword": true,
              "enforceNumericCharacters": false,
              "enforceSpecialCharacters": false,
              "enforceUpperLowerCase": false
            },
            "provisioning_api": {
              "version": "2.0.0-dev.0",
              "AccountPropertyScopesVersion": 2,
              "AccountPropertyScopesFederatedEnabled": true,
              "AccountPropertyScopesPublishedEnabled": false
            },
            "spreed": {
              "features": [
                "audio",
                "video",
                "chat-v2",
                "conversation-v4",
                "guest-signaling",
                "empty-group-room",
                "guest-display-names",
                "multi-room-users",
                "favorites",
                "last-room-activity",
                "no-ping",
                "system-messages",
                "delete-messages",
                "mention-flag",
                "in-call-flags",
                "conversation-call-flags",
                "notification-levels",
                "invite-groups-and-mails",
                "locked-one-to-one-rooms",
                "read-only-rooms",
                "listable-rooms",
                "chat-read-marker",
                "chat-unread",
                "webinary-lobby",
                "start-call-flag",
                "chat-replies",
                "circles-support",
                "force-mute",
                "sip-support",
                "sip-support-nopin",
                "chat-read-status",
                "phonebook-search",
                "raise-hand",
                "room-description",
                "rich-object-sharing",
                "temp-user-avatar-api",
                "geo-location-sharing",
                "voice-message-sharing",
                "signaling-v3",
                "publishing-permissions",
                "clear-history",
                "direct-mention-flag",
                "notification-calls",
                "conversation-permissions",
                "rich-object-list-media",
                "rich-object-delete",
                "unified-search",
                "chat-permission",
                "react-permission",
                "silent-send",
                "silent-call",
                "send-call-notification",
                "talk-polls",
                "breakout-rooms-v1",
                "recording-v1",
                "avatar",
                "chat-get-context",
                "single-conversation-status",
                "chat-keep-notifications",
                "typing-privacy",
                "remind-me-later",
                "bots-v1",
                "markdown-messages",
                "media-caption",
                "session-state",
                "note-to-self",
                "recording-consent",
                "sip-support-dialout",
                "delete-messages-unlimited",
                "edit-messages",
                "silent-send-state",
                "chat-read-last",
                "federation-v1",
                "federation-v2",
                "ban-v1",
                "chat-reference-id",
                "mention-permissions",
                "edit-messages-note-to-self",
                "archived-conversations-v2",
                "talk-polls-drafts",
                "download-call-participants",
                "email-csv-import",
                "conversation-creation-password",
                "call-notification-state-api",
                "schedule-meeting",
                "edit-draft-poll",
                "conversation-creation-all",
                "important-conversations",
                "unbind-conversation",
                "sip-direct-dialin",
                "dashboard-event-rooms",
                "mutual-calendar-events",
                "upcoming-reminders",
                "sensitive-conversations",
                "threads",
                "pinned-messages",
                "federated-shared-items",
                "scheduled-messages",
                "conversation-presets",
                "private-reply",
                "conversation-tags",
                "preserve-conversation",
                "classified-conversations",
                "message-expiration",
                "reactions",
                "call-end-to-end-encryption"
              ],
              "features-local": [
                "favorites",
                "chat-read-status",
                "listable-rooms",
                "phonebook-search",
                "temp-user-avatar-api",
                "unified-search",
                "avatar",
                "remind-me-later",
                "note-to-self",
                "archived-conversations-v2",
                "chat-summary-api",
                "call-notification-state-api",
                "schedule-meeting",
                "conversation-creation-all",
                "important-conversations",
                "sip-direct-dialin",
                "dashboard-event-rooms",
                "mutual-calendar-events",
                "upcoming-reminders",
                "sensitive-conversations",
                "scheduled-messages",
                "conversation-presets",
                "conversation-tags",
                "recording-chunked-upload",
                "classified-conversations"
              ],
              "config": {
                "attachments": {
                  "allowed": true,
                  "conversation-subfolders": true,
                  "folder": "/Talk"
                },
                "call": {
                  "enabled": true,
                  "breakout-rooms": true,
                  "recording": false,
                  "recording-consent": 0,
                  "supported-reactions": [
                    "❤️",
                    "🎉",
                    "👏",
                    "👋",
                    "👍",
                    "👎",
                    "🔥",
                    "😂",
                    "🤩",
                    "🤔",
                    "😲",
                    "😥"
                  ],
                  "can-upload-background": true,
                  "sip-enabled": true,
                  "sip-dialout-enabled": true,
                  "default-phone-region": "DE",
                  "can-enable-sip": true,
                  "start-without-media": false,
                  "max-duration": 0,
                  "blur-virtual-background": false,
                  "end-to-end-encryption": false,
                  "live-transcription": false,
                  "live-translation": false,
                  "play-sounds": true,
                  "grid-limit": 19,
                  "grid-limit-enforced": false,
                  "predefined-backgrounds": [
                    "1_office.jpg",
                    "2_home.jpg",
                    "3_abstract.jpg",
                    "4_beach.jpg",
                    "5_park.jpg",
                    "6_theater.jpg",
                    "7_library.jpg",
                    "8_space_station.jpg"
                  ],
                  "predefined-backgrounds-v2": [
                    "/apps-extra/spreed/img/backgrounds/1_office.jpg",
                    "/apps-extra/spreed/img/backgrounds/2_home.jpg",
                    "/apps-extra/spreed/img/backgrounds/3_abstract.jpg",
                    "/apps-extra/spreed/img/backgrounds/4_beach.jpg",
                    "/apps-extra/spreed/img/backgrounds/5_park.jpg",
                    "/apps-extra/spreed/img/backgrounds/6_theater.jpg",
                    "/apps-extra/spreed/img/backgrounds/7_library.jpg",
                    "/apps-extra/spreed/img/backgrounds/8_space_station.jpg"
                  ],
                  "live-transcription-target-language-id": ""
                },
                "chat": {
                  "max-length": 32000,
                  "read-privacy": 0,
                  "has-translation-providers": false,
                  "has-translation-task-providers": false,
                  "typing-privacy": 0,
                  "summary-threshold": 100,
                  "style": "split",
                  "matterbridge-enabled": false
                },
                "conversations": {
                  "can-create": true,
                  "force-passwords": false,
                  "list-style": "two-lines",
                  "sort-order": "activity",
                  "group-mode": "none",
                  "description-length": 2000,
                  "retention-event": 28,
                  "retention-phone": 7,
                  "retention-instant-meetings": 1,
                  "retention-classified": 3600
                },
                "federation": {
                  "enabled": true,
                  "incoming-enabled": true,
                  "outgoing-enabled": true,
                  "only-trusted-servers": false
                },
                "previews": {
                  "max-gif-size": 3145728
                },
                "signaling": {
                  "session-ping-limit": 200,
                  "mode": "external",
                  "hello-v2-token-key": "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEierxyrWlum+xtPBhfno/KXUVD3UV\nI9saeP3YmjYufP93XZc003kK859wRvAsa/O7oAv6l3Ibp40fAsWfinSTFA==\n-----END PUBLIC KEY-----\n"
                },
                "experiments": {
                  "enabled": 0
                },
                "feature-hints": {
                  "current": 34,
                  "hidden": 0
                },
                "permissions": {
                  "max-default": 510,
                  "max-custom": 511,
                  "default": 502
                }
              },
              "config-local": {
                "attachments": [
                  "allowed",
                  "folder",
                  "conversation-subfolders"
                ],
                "call": [
                  "predefined-backgrounds",
                  "predefined-backgrounds-v2",
                  "can-upload-background",
                  "start-without-media",
                  "blur-virtual-background",
                  "live-transcription-target-language-id",
                  "play-sounds",
                  "grid-limit",
                  "grid-limit-enforced",
                  "external-call-service"
                ],
                "chat": [
                  "read-privacy",
                  "has-translation-providers",
                  "has-translation-task-providers",
                  "typing-privacy",
                  "summary-threshold",
                  "style",
                  "matterbridge-enabled"
                ],
                "conversations": [
                  "can-create",
                  "list-style",
                  "sort-order",
                  "group-mode",
                  "description-length"
                ],
                "federation": [
                  "enabled",
                  "incoming-enabled",
                  "outgoing-enabled",
                  "only-trusted-servers"
                ],
                "previews": [
                  "max-gif-size"
                ],
                "signaling": [
                  "session-ping-limit",
                  "mode",
                  "hello-v2-token-key"
                ],
                "experiments": [
                  "enabled"
                ],
                "feature-hints": [
                  "current",
                  "hidden"
                ],
                "permissions": []
              },
              "version": "25.0.0-dev.0"
            },
            "systemtags": {
              "enabled": true
            },
            "theming": {
              "name": "ABCD",
              "productName": "Nextcloud",
              "url": "https://nextcloud.com",
              "imprintUrl": "",
              "privacyUrl": "",
              "slogan": "ein sicherer Ort für all Ihre Daten",
              "color": "#00679e",
              "color-text": "#ffffff",
              "color-element": "#00679e",
              "color-element-bright": "#00679e",
              "color-element-dark": "#00679e",
              "logo": "https://nextcloud-mm.local/core/img/logo/logo.svg?v=1",
              "background": "https://nextcloud-mm.local/apps/theming/img/background/jo-myoung-hee-fluid.webp",
              "background-text": "#ffffff",
              "background-plain": false,
              "background-default": true,
              "logoheader": "https://nextcloud-mm.local/core/img/logo/logo.svg?v=1",
              "favicon": "https://nextcloud-mm.local/core/img/logo/logo.svg?v=1",
              "primaryColor": "#00679e",
              "backgroundColor": "#00679e",
              "defaultPrimaryColor": "#00679e",
              "defaultBackgroundColor": "#00679e",
              "inverted": false,
              "cacheBuster": "9c0d6eeb",
              "enabledThemes": [
                "default"
              ]
            },
            "user_status": {
              "enabled": true,
              "restore": true,
              "supports_emoji": true,
              "supports_busy": true
            },
            "weather_status": {
              "enabled": true
            }
          }
        }
      }
    }
    """#
}
