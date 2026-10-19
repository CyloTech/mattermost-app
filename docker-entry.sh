#!/bin/bash
# Copyright (c) 2016 Mattermost, Inc. All Rights Reserved.
# See License.txt for license information.

echo "Starting Postgres"
# Postgres is never running when the container starts, so a postmaster.pid
# left by a container that was killed is stale. Postgres refuses to start if
# the PID in it now belongs to another process in this container.
rm -f /var/lib/postgresql/data/postmaster.pid
mkdir -p /mm /var/lib/postgresql/data /var/run/postgresql
chown -R 1000:1000 /mm /var/lib/postgresql /var/run/postgresql
gosu 1000:1000 /usr/local/bin/docker-entrypoint.sh postgres &
postgres_pid=$!
mattermost_pid=

stop_postgres() {
    gosu 1000:1000 pg_ctl stop -m fast -w -t 20
    wait "$postgres_pid"
}

# Docker sends the stop signal here. Stop Mattermost first, then shut
# Postgres down cleanly so it does not need crash recovery on the next start.
shutdown() {
    trap - TERM INT
    echo "Stopping Mattermost and Postgres"
    if [ -n "$mattermost_pid" ]; then
        kill -TERM "$mattermost_pid" 2>/dev/null
        wait "$mattermost_pid"
    fi
    stop_postgres
    exit 0
}
trap shutdown TERM INT

until gosu 1000:1000 pg_isready -h 127.0.0.1 -p 5432 -U postgres -d "${POSTGRES_DB:-mattermost}" >/dev/null 2>&1; do
  >&2 echo "Postgres is unavailable - sleeping for 5 seconds"
  sleep 5
done

if [ ! -f /etc/app_configured ]; then
    # Copy over files
    cd /mm || exit 1
    wget https://releases.mattermost.com/12.0.0/mattermost-12.0.0-linux-amd64.tar.gz .
    tar -zxvf ./mattermost-12.0.0-linux-amd64.tar.gz

    if [[ ! -f /mm/mattermost/config/config_docker.json ]]; then
        mv /config_docker.json /mm/mattermost/config/config_docker.json
    fi

    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
    touch /etc/app_configured
fi

chown -R 1000:1000 /mm/ /var/lib/postgresql/data

echo "Starting platform"
cd /mm/mattermost || exit 1
gosu 1000:1000 ./bin/mattermost --config=config/config_docker.json &
mattermost_pid=$!
wait "$mattermost_pid"
mattermost_status=$?

# Mattermost exited by itself; keep the container's exit status but still
# leave the database cleanly.
stop_postgres
exit "$mattermost_status"
