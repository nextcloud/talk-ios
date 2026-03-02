#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# This script is intended to setup specific rooms that we want to test

SERVER_URL="http://localhost:8080"

# Check if a Talk capability is available
# Usage: has_capability "capability-name"
has_capability() {
    local capability="$1"
    curl -s -u admin:admin "$SERVER_URL/ocs/v2.php/cloud/capabilities" \
        -H "OCS-APIRequest: true" \
        -H 'accept: application/json, text/plain, */*' \
        | jq -e ".ocs.data.capabilities.spreed.features | any(. == \"$capability\")" > /dev/null 2>&1
}

# Setup a room with lobby enabled and add admin as a normal participant
response=$(curl -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v4/room" \
    -H "OCS-APIRequest: true" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/plain, */*' \
    --data-raw '{"roomType":2,"roomName":"LobbyTest"}')

echo $response

token=$(echo $response | jq -r .ocs.data.token)

echo $token

curl -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v4/room/$token/webinar/lobby" \
    -X 'PUT' \
    -H "OCS-APIRequest: true" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/plain, */*' \
    --data-raw '{"state":1}'

curl -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v4/room/$token/participants" \
    -H "OCS-APIRequest: true" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/plain, */*' \
    --data-raw '{"newParticipant":"admin","source":"users"}'

# Setup a listable room so other users can join them
response=$(curl -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v4/room" \
    -H "OCS-APIRequest: true" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/plain, */*' \
    --data-raw '{"roomType":2,"roomName":"OpenConversationTest"}')

echo $response

token=$(echo $response | jq -r .ocs.data.token)

echo $token

curl -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v4/room/$token/listable" \
    -X 'PUT' \
    -H "OCS-APIRequest: true" \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/plain, */*' \
    --data-raw '{"scope":1}'

# Setup a room with react-only permission (can react but cannot chat)
# Only available when server supports react-permission capability (Talk 24+)
if has_capability "react-permission"; then
    echo "Setting up ReactOnlyTest room (react-permission capability detected)"

    # Permission values: CustomPermissions=1 (auto-added), JoinCall=4, React=256
    # Total: 260 (4 + 256, custom flag auto-added when non-zero)
    response=$(curl -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v4/room" \
        -H "OCS-APIRequest: true" \
        -H 'content-type: application/json' \
        -H 'accept: application/json, text/plain, */*' \
        --data-raw '{"roomType":2,"roomName":"ReactOnlyTest"}')

    echo $response

    token=$(echo $response | jq -r .ocs.data.token)

    echo "ReactOnlyTest token: $token"

    # Set default permissions to react-only (no chat permission)
    # 260 = JoinCall(4) + React(256)
    curl -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v4/room/$token/permissions/default" \
        -X 'PUT' \
        -H "OCS-APIRequest: true" \
        -H 'content-type: application/json' \
        -H 'accept: application/json, text/plain, */*' \
        --data-raw '{"permissions":260}'

    # Add admin as a participant (will get the default react-only permissions)
    curl -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v4/room/$token/participants" \
        -H "OCS-APIRequest: true" \
        -H 'content-type: application/json' \
        -H 'accept: application/json, text/plain, */*' \
        --data-raw '{"newParticipant":"admin","source":"users"}'

    # Send a message from alice (moderator) so there's something to react to
    curl -X POST -u alice:alice "$SERVER_URL/ocs/v2.php/apps/spreed/api/v1/chat/$token" \
        -H "OCS-APIRequest: true" \
        -H 'content-type: application/json' \
        -H 'accept: application/json' \
        --data-raw '{"message":"React to this message!"}'
else
    echo "Skipping ReactOnlyTest room setup (react-permission capability not available)"
fi
