#!/usr/bin/env bash
# Based on the script from Milen Pivchev in nextcloud/ios repository

# This script runs the CI scripts needed to set up a test instance and install talk locally

CONTAINER_NAME=nextcloud_test
TEST_BRANCH=master
SERVER_PORT=8080

source ./ci-create-docker-server.sh
source ./ci-wait-for-server.sh
source ./ci-install-talk.sh
