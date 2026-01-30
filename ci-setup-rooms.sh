#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# This script is intended to setup specific rooms that we want to test

# Setup a room with lobby enabled and add admin as a normal participant
response=$(curl -u alice:alice 'http://localhost:8080/ocs/v2.php/apps/spreed/api/v4/room' \
    -H "OCS-APIRequest: true" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/plain, */*' \
    --data-raw '{"roomType":2,"roomName":"LobbyTest"}')

echo $response

token=$(echo $response | jq -r .ocs.data.token)

echo $token

curl -u alice:alice "http://localhost:8080/ocs/v2.php/apps/spreed/api/v4/room/$token/webinar/lobby" \
    -X 'PUT' \
    -H "OCS-APIRequest: true" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/plain, */*' \
    --data-raw '{"state":1}'

curl -u alice:alice "http://localhost:8080/ocs/v2.php/apps/spreed/api/v4/room/$token/participants" \
    -H "OCS-APIRequest: true" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/plain, */*' \
    --data-raw '{"newParticipant":"admin","source":"users"}'

# Setup a room with react-only permission (can react but cannot chat)
# Only available in Talk 24+ (main/stable34+), as react-permission capability was introduced then
if [ "$TALK_BRANCH" = "main" ] || [ "$TALK_BRANCH" = "stable34" ]; then
    echo "Setting up ReactOnlyTest room (Talk 24+ feature)"

    # Permission values: CustomPermissions=1 (auto-added), JoinCall=4, React=256
    # Total: 260 (4 + 256, custom flag auto-added when non-zero)
    response=$(curl -u alice:alice 'http://localhost:8080/ocs/v2.php/apps/spreed/api/v4/room' \
        -H "OCS-APIRequest: true" \
        -H 'content-type: application/json' \
        -H 'accept: application/json, text/plain, */*' \
        --data-raw '{"roomType":2,"roomName":"ReactOnlyTest"}')

    echo $response

    token=$(echo $response | jq -r .ocs.data.token)

    echo "ReactOnlyTest token: $token"

    # Set default permissions to react-only (no chat permission)
    # 260 = JoinCall(4) + React(256)
    curl -u alice:alice "http://localhost:8080/ocs/v2.php/apps/spreed/api/v4/room/$token/permissions/default" \
        -X 'PUT' \
        -H "OCS-APIRequest: true" \
        -H 'content-type: application/json' \
        -H 'accept: application/json, text/plain, */*' \
        --data-raw '{"permissions":260}'

    # Add admin as a participant (will get the default react-only permissions)
    curl -u alice:alice "http://localhost:8080/ocs/v2.php/apps/spreed/api/v4/room/$token/participants" \
        -H "OCS-APIRequest: true" \
        -H 'content-type: application/json' \
        -H 'accept: application/json, text/plain, */*' \
        --data-raw '{"newParticipant":"admin","source":"users"}'

    # Send a message from alice (moderator) so there's something to react to
    curl -u alice:alice "http://localhost:8080/ocs/v2.php/apps/spreed/api/v4/chat/$token" \
        -H "OCS-APIRequest: true" \
        -H 'content-type: application/json' \
        -H 'accept: application/json, text/plain, */*' \
        --data-raw '{"message":"React to this message!"}'
else
    echo "Skipping ReactOnlyTest room setup (requires Talk 24+, current branch: $TALK_BRANCH)"
fi
