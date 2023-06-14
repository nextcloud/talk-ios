#!/usr/bin/env bash
# Based on the script from Milen Pivchev in nextcloud/ios repository

# This script installs docker and starts a nextcloud test instance

echo "Setup docker..."

brew install docker
colima start

echo "Creating nextcloud instance for branch $TEST_BRANCH..."

docker run --rm -d \
    --name $CONTAINER_NAME \
    -e SERVER_BRANCH=$TEST_BRANCH \
    -p $SERVER_PORT:80 \
    ghcr.io/juliushaertl/nextcloud-dev-php80:latest