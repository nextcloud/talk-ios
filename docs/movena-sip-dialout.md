# Movena SIP dialout adaptation

This fork adds native iOS controls for the Movena phone bridge while keeping SIP
credentials and callback secrets on the server side.

The app does not register as a SIP user agent and does not embed PBX credentials.
Instead, it uses the logged-in Nextcloud account to call existing OCS endpoints on
the connected Nextcloud server.

## Architecture

The iOS app remains a Nextcloud Talk WebRTC client. Phone calls are routed through
the existing server-side bridge:

```text
Nextcloud Talk iOS
  -> Nextcloud Talk OCS API
  -> Talk HPB / standalone signaling
  -> Movena HPB dialout client
  -> PBX callback service
  -> SIPMediaGW / PBX
```

Movena-specific in-call controls use:

```text
Nextcloud Talk iOS
  -> /ocs/v2.php/apps/movena_call/api/v1/overlay/*
  -> movena_call server app
  -> PBX callback service
```

This mirrors the browser and desktop Movena integrations, but uses native iOS UI
instead of injecting the browser overlay.

## Runtime requirements

The connected Nextcloud server must have:

- Nextcloud Talk with SIP configured.
- Talk capability `sip-support-dialout`.
- Talk SIP dialout enabled on the server.
- A group or public conversation, because Talk only allows phone participants for
  those conversation types.
- A current user who can moderate the conversation and is allowed to use SIP
  dialout by server-side Talk configuration.

The Movena phone controls additionally require:

- The `movena_call` app installed and enabled on the server.
- `movena_call callback_token` configured on the server.
- `movena_call callback_url` or per-action callback URLs configured for transfer,
  DTMF, and hangup.
- The current user allowed by the `movena_call allowed_group` configuration, if
  that restriction is enabled.

## User flow

When the user is in a supported call, the moderator menu shows:

```text
Call phone number
```

The app then:

1. Adds the typed phone number to the room as a `phones` attendee.
2. Refreshes room participants.
3. Starts Talk SIP dialout for the added phone attendee.

When Movena phone controls are available, the in-call More menu shows:

```text
Phone controls
```

The submenu exposes:

- Send DTMF
- Start transfer
- Hold transfer
- Complete transfer
- Cancel transfer
- Hang up phone participant

These controls call the `movena_call` OCS overlay endpoints with the user's
normal Nextcloud authentication. The callback token remains server-side.

## Code map

Phone attendee support:

- `NextcloudTalk/Contacts/NCUser.h`
- `NextcloudTalk/Contacts/NCUser.m`
- `NextcloudTalk/Rooms/NCRoomParticipant.swift`

Capability support:

- `NextcloudTalk/Database/NCDatabaseManager.swift`

OCS API helpers:

- `NextcloudTalk/Network/NCAPIController.swift`

Native in-call UI:

- `NextcloudTalk/Calls/CallViewController.swift`

## OCS endpoints used

Talk SIP dialout:

```text
POST /ocs/v2.php/apps/spreed/api/v4/room/{token}/participants
POST /ocs/v2.php/apps/spreed/api/v4/call/{token}/dialout/{attendeeId}
```

Movena phone controls:

```text
POST /ocs/v2.php/apps/movena_call/api/v1/overlay/dtmf
POST /ocs/v2.php/apps/movena_call/api/v1/overlay/transfer
POST /ocs/v2.php/apps/movena_call/api/v1/overlay/hangup
```

## Validation checklist

Before shipping an iOS build, verify on macOS with Xcode:

```sh
pod install
open NextcloudTalk.xcworkspace
```

Then test:

1. Log in to the Movena Nextcloud server.
2. Open a group or public Talk conversation.
3. Join the call as a moderator.
4. Use `Call phone number` and confirm the PSTN side rings.
5. Confirm the phone attendee appears in the participant list.
6. Send DTMF digits during the bridged call.
7. Start, hold, complete, and cancel a transfer.
8. Hang up the phone participant from the More menu.

Also run the normal project checks available to the build machine:

```sh
swiftlint
xcodebuild test -workspace NextcloudTalk.xcworkspace \
    -scheme "NextcloudTalk" \
    -destination "platform=iOS Simulator,name=iPhone 16,OS=18.5"
```

## Notes

This adaptation intentionally keeps the app on the existing Nextcloud Talk and
Movena bridge path. A true native iOS SIP softphone would require a separate SIP
stack, background-call handling, PBX credential storage, and additional App Store
review considerations.
