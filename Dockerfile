# Copyright (c) 2016 Mattermost, Inc. All Rights Reserved.
# See License.txt for license information.
FROM postgres:16

RUN apt-get update && apt-get install -y ca-certificates wget curl

ENV POSTGRES_PASSWORD=mmdefault
ENV POSTGRES_DB=mattermost

ADD config_docker.json /config_docker.json
ADD docker-entry.sh /
RUN chmod +x ./docker-entry.sh
ENTRYPOINT ./docker-entry.sh

EXPOSE 80
