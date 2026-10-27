#!/bin/bash
# Copyright (c) 2016 Mattermost, Inc. All Rights Reserved.
# See License.txt for license information.

MM_CONFIG=/mm/mattermost/config/config_docker.json
PG_DATA=/var/lib/postgresql/data
# Database superuser password of an install created by this image or a later
# one. Installs created by older images have no file and keep the password
# they were created with.
DB_PASSWORD_FILE=/mm/.db_password
# Created once ConsoleLevel has been changed from DEBUG to INFO, so that a
# level the owner picks later is kept.
CONSOLE_LEVEL_DONE=/mm/.console_level_info

# Writes a new random password file that only the database user can read.
new_db_password() {
    local password
    password=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')
    if [[ ! $password =~ ^[0-9a-f]{64}$ ]]; then
        echo "Could not generate a database password" >&2
        return 1
    fi
    (umask 077 && printf '%s' "$password" > "$DB_PASSWORD_FILE.new") || return 1
    chown 1000:1000 "$DB_PASSWORD_FILE.new" &&
        mv "$DB_PASSWORD_FILE.new" "$DB_PASSWORD_FILE"
}

# Writes the Mattermost configuration of a new install. The password only
# passes through shell builtins, so it never appears in a command line.
write_config() {
    local template password
    template=$(< /config_docker.json) || return 1
    if [ -s "$DB_PASSWORD_FILE" ]; then
        password=$(< "$DB_PASSWORD_FILE")
    else
        # The database was created by an older image with this password.
        # It only accepts connections from inside the container.
        password=mmdefault
    fi
    (umask 077 && printf '%s\n' "${template/__DB_PASSWORD__/$password}" > "$MM_CONFIG.new") || return 1
    chown 1000:1000 "$MM_CONFIG.new" &&
        mv "$MM_CONFIG.new" "$MM_CONFIG"
}

echo "Starting Postgres"
# Postgres is never running when the container starts, so a postmaster.pid
# left by a container that was killed is stale. Postgres refuses to start if
# the PID in it now belongs to another process in this container.
rm -f "$PG_DATA/postmaster.pid"
mkdir -p /mm "$PG_DATA" /var/run/postgresql
chown -R 1000:1000 /mm /var/lib/postgresql /var/run/postgresql

# Only Mattermost in this container uses Postgres, so it listens on the
# loopback address only, whatever the database's own configuration says.
postgres_cmd=(/usr/local/bin/docker-entrypoint.sh postgres -c listen_addresses=127.0.0.1)
if [ -s "$PG_DATA/PG_VERSION" ]; then
    gosu 1000:1000 env -u POSTGRES_PASSWORD "${postgres_cmd[@]}" &
else
    # A new database gets its own superuser password, and TCP connections
    # must give it.
    if [ ! -s "$DB_PASSWORD_FILE" ]; then
        new_db_password || exit 1
    fi
    gosu 1000:1000 env -u POSTGRES_PASSWORD \
        POSTGRES_PASSWORD_FILE="$DB_PASSWORD_FILE" \
        POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 \
        "${postgres_cmd[@]}" &
fi
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

    if [[ ! -f "$MM_CONFIG" ]]; then
        if ! write_config; then
            echo "Could not write $MM_CONFIG" >&2
            stop_postgres
            exit 1
        fi
    fi

    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/$INSTANCE_ID"
    touch /etc/app_configured
fi

# Older images set the console log level to DEBUG. Change it to INFO once.
if [ ! -e "$CONSOLE_LEVEL_DONE" ] && [ -f "$MM_CONFIG" ]; then
    sed -i 's/"ConsoleLevel": "DEBUG"/"ConsoleLevel": "INFO"/' "$MM_CONFIG" &&
        touch "$CONSOLE_LEVEL_DONE"
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
