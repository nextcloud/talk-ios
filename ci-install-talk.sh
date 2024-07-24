#!/usr/bin/env bash
# Based on the script from Milen Pivchev in nextcloud/ios repository

# SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-3.0-or-later

# This script downloads and installs talk

echo "Installing talk"
docker exec $CONTAINER_NAME git clone --depth 1 --branch $TEST_BRANCH https://github.com/nextcloud/spreed.git /var/www/html/apps-extra/spreed
docker exec $CONTAINER_NAME composer i --working-dir=/var/www/html/apps-extra/spreed/
docker exec $CONTAINER_NAME chown -R www-data:www-data /var/www/html/apps-extra/
docker exec $CONTAINER_NAME sudo -E -u www-data php /var/www/html/occ app:enable --force spreed
