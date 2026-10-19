#!/bin/bash
# Copyright (c) 2016 Mattermost, Inc. All Rights Reserved.
# See License.txt for license information.

echo "Starting Postgres"
mkdir -p /mm /var/lib/postgresql/data /var/run/postgresql
chown -R 1000:1000 /mm /var/lib/postgresql /var/run/postgresql
gosu 1000:1000 /usr/local/bin/docker-entrypoint.sh postgres &

until gosu 1000:1000 pg_isready -h 127.0.0.1 -p 5432 -U postgres -d "${POSTGRES_DB:-mattermost}" >/dev/null 2>&1; do
  >&2 echo "Postgres is unavailable - sleeping for 5 seconds"
  sleep 5
done

if [ ! -f /etc/app_configured ]; then
    # Copy over files
    cd /mm || exit 1
    wget https://releases.mattermost.com/11.3.0/mattermost-11.3.0-linux-amd64.tar.gz .
    tar -zxvf ./mattermost-11.3.0-linux-amd64.tar.gz

    if [[ ! -f /mm/mattermost/config/config_docker.json ]]; then
        mv /config_docker.json /mm/mattermost/config/config_docker.json
    fi

    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
    touch /etc/app_configured
fi

chown -R 1000:1000 /mm/ /var/lib/postgresql/data

echo "Starting platform"
cd /mm/mattermost || exit 1
exec gosu 1000:1000 ./bin/mattermost --config=config/config_docker.json
