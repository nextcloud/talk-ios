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
