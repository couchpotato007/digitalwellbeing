# The server. Build from the repo root, it needs shared/ too:
#   docker build -t digitalwellbeing .

ARG GLEAM_VERSION=v1.19.2
ARG ERLANG_IMAGE=erlang:28-alpine

FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-scratch AS gleam

FROM ${ERLANG_IMAGE} AS build
COPY --from=gleam /bin/gleam /bin/gleam
# esqlite compiles SQLite as a NIF
RUN apk add --no-cache build-base
COPY shared /src/shared
COPY server /src/server
WORKDIR /src/server
RUN gleam export erlang-shipment

FROM ${ERLANG_IMAGE}
# tzdata so TZ works, days on the dashboard are counted in local time
RUN apk add --no-cache tzdata \
 && adduser -D -u 1000 app \
 && mkdir /data && chown app:app /data
COPY --from=build /src/server/build/erlang-shipment /app
USER app
ENV CONFIG_DIR=/data PORT=8080
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
