#!/usr/bin/env bash
# Based on the script from Milen Pivchev in nextcloud/ios repository

# SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# This script runs the CI scripts needed to set up a test instance and install talk locally

CONTAINER_NAME=nextcloud_test
TEST_BRANCH=main
SERVER_PORT=8080

source ./ci-create-docker-server.sh
source ./ci-wait-for-server.sh
source ./ci-install-talk.sh
source ./ci-setup-rooms.sh
