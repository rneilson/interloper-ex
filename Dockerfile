ARG ELIXIR_VERSION=1.14
# Elixir image uses erlang:25-alpine, which uses alpine:3.16
ARG ALPINE_VERSION=3.16

## Build image
FROM elixir:${ELIXIR_VERSION}-alpine AS builder

# Build settings (mostly regarding HTTPS)
ARG MIX_ENV=prod
ARG SITE_SCHEME=https
ARG SITE_TLS_CRT=true
ARG SITE_TLS_HSTS=false

# Env var versions of above
ENV MIX_ENV=${MIX_ENV} \
    SITE_SCHEME=${SITE_SCHEME} \
    SITE_TLS_CRT=${SITE_TLS_CRT} \
    SITE_TLS_HSTS=${SITE_TLS_HSTS}

# Install build tools
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache \
        git \
        nodejs \
        npm \
        build-base

# Create user (to avoid perm issues later)
RUN addgroup -g 1000 user && \
    adduser -D -u 1000 -G user user && \
    mkdir -p /opt/build && \
    chown 1000:1000 /opt/build && \
    mkdir -p /opt/app/deps && \
    chown -R 1000:1000 /opt/app
USER 1000:1000

RUN mix local.rebar --force && \
    mix local.hex --force

# Set build dir, copy source
WORKDIR /opt/app
COPY --chown=1000:1000 . .

# Fetch and compile dependencies and source
RUN mkdir -p deps && \
    mix do deps.get, deps.compile, compile

# Build web assets
RUN cd apps/interloper_web/assets && \
    NODE_ENV=production && \
    npm install && \
    npm run deploy && \
    cd ../../.. && \
    mix phx.digest

# Build release
RUN mkdir -p /opt/build && \
    mix distillery.release --verbose && \
    RELEASES_DIR="$(pwd)/_build/${MIX_ENV}/rel/interloper_ex/releases" && \
    REL_VSN="$(cut -d' ' -f2 "${RELEASES_DIR}"/start_erl.data)" && \
    cp "${RELEASES_DIR}/${REL_VSN}/interloper_ex.tar.gz" /opt/build/ && \
    cd /opt/build && \
    tar -xzf "interloper_ex.tar.gz" && \
    rm "interloper_ex.tar.gz"


## Release image
FROM alpine:${ALPINE_VERSION}

# Install runtime deps
RUN apk update && \
    apk add --no-cache \
        bash \
        openssl-dev \
        libcap \
        ca-certificates

# Create user (to avoid perm issues later)
RUN addgroup -g 1000 user && \
    adduser -D -u 1000 -G user user

# Set build dir, copy source
WORKDIR /opt/app
COPY --from=builder --chown=1000:1000 /opt/build .

# Use the release's script as the entrypoint
ENTRYPOINT ["/opt/app/bin/interloper_ex"]
CMD ["foreground"]

# Allow binding to restricted ports
# Also sneak in creating the writable dir
RUN ERTS_VSN="$(cut -d' ' -f1 releases/start_erl.data)" && \
    setcap CAP_NET_BIND_SERVICE=+eip "erts-${ERTS_VSN}/bin/beam.smp" && \
    mkdir -p var && \
    chown 1000:1000 var

# *Now* set user
USER 1000:1000

# Some vars previously defined
ARG MIX_ENV=prod
ARG SITE_NAME=www.interloper.ca
ARG SITE_SCHEME=https
ARG SITE_TLS_CRT=/opt/app/tls/${SITE_NAME}.pem
ARG SITE_TLS_KEY=/opt/app/tls/${SITE_NAME}.key
# ARG SITE_TLS_CA=/opt/app/tls/${SITE_NAME}_chain.pem

# Copy TLS cert(s)
COPY --chown=1000:1000 tls/ tls/

# Set env
ENV MIX_ENV=${MIX_ENV} \
    SITE_NAME=${SITE_NAME} \
    SITE_SCHEME=${SITE_SCHEME} \
    SITE_TLS_CRT=${SITE_TLS_CRT} \
    SITE_TLS_KEY=${SITE_TLS_KEY}
    # SITE_TLS_CA=${SITE_TLS_CA}
