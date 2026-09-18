FROM postgres:17.2-alpine

COPY init-scripts/ /docker-entrypoint-initdb.d/