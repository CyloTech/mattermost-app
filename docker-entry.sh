#!/bin/bash
# Copyright (c) 2016 Mattermost, Inc. All Rights Reserved.
# See License.txt for license information.

echo "Starting MySQL"
/entrypoint.sh mysqld &

until mysqladmin -hlocalhost -P3306 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" processlist &> /dev/null; do
	echo "MySQL still not ready, sleeping"
	sleep 5
done

if [ ! -f /etc/app_configured ]; then
    # Copy over files
    cd /mm
    wget https://releases.mattermost.com/4.9.0/mattermost-team-4.9.0-linux-amd64.tar.gz .
    tar -zxvf ./mattermost-team-4.9.0-linux-amd64.tar.gz
    mv /config_docker.json /mm/mattermost/config/config_docker.json

    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
    touch /etc/app_configured
fi

echo "Starting platform"
cd /mm/mattermost
exec ./bin/platform --config=config/config_docker.json
