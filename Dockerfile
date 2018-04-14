# Copyright (c) 2016 Mattermost, Inc. All Rights Reserved.
# See License.txt for license information.
FROM mysql:5.7

RUN apt-get update && apt-get install -y ca-certificates wget curl

ENV MYSQL_ROOT_PASSWORD=mysqlr00t
ENV MYSQL_USER=mmdefault
ENV MYSQL_PASSWORD=mmdefault
ENV MYSQL_DATABASE=mattermost


ADD config_docker.json /config_docker.json
ADD docker-entry.sh /
RUN chmod +x ./docker-entry.sh
ENTRYPOINT ./docker-entry.sh

EXPOSE 80
