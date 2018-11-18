#
# Build stage by @abiosoft https://github.com/abiosoft/caddy-docker
#
FROM golang:1.11-alpine as build

ARG BUILD_DATE
ARG VCS_REF
ARG DEBIAN_FRONTED=noninteractive

ARG caddy_version="v0.11.1"
ARG plugins="cache,expires,git,jwt,prometheus,realip,reauth"

RUN apk add --no-cache --no-progress git

# caddy
RUN git clone https://github.com/mholt/caddy -b "${caddy_version}" /go/src/github.com/mholt/caddy \
    && cd /go/src/github.com/mholt/caddy \
    && git checkout -b "${caddy_version}"

# plugin helper
RUN go get -v github.com/abiosoft/caddyplug/caddyplug

# plugins
RUN for plugin in $(echo $plugins | tr "," " "); do \
    go get -v $(caddyplug package $plugin); \
    printf "package caddyhttp\nimport _ \"$(caddyplug package $plugin)\"" > \
        /go/src/github.com/mholt/caddy/caddyhttp/$plugin.go ; \
    done

# builder dependency
RUN git clone https://github.com/caddyserver/builds /go/src/github.com/caddyserver/builds

# build with telemetry enabled
RUN cd /go/src/github.com/mholt/caddy/caddy \
    && git checkout -f \
    && go run build.go \
    && mv caddy /go/bin


#
# Compress Caddy with upx
#
FROM debian:stable as compress

# curl, tar
RUN apt-get update && apt install -y --no-install-recommends \
    tar \
    xz-utils \
    curl \
    ca-certificates

# get official upx binary
RUN curl --silent --show-error --fail --location -o - \
    "https://github.com/upx/upx/releases/download/v3.95/upx-3.95-amd64_linux.tar.xz" \
    | tar --no-same-owner -C /usr/bin/ -xJ \
    --strip-components 1 upx-3.95-amd64_linux/upx

# copy and compress
COPY --from=build /go/bin/caddy /usr/bin/caddy
RUN /usr/bin/upx --ultra-brute /usr/bin/caddy

# test
RUN /usr/bin/caddy -version
RUN /usr/bin/caddy -plugins

#
# Final image
#
FROM scratch

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-url="https://github.com/swarmstack/caddy.git" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.schema-version="1.0.0-rc1"

MAINTAINER Mike Holloway <mikeholloway+swarmstack@gmail.com>

# copy caddy binary and ca certs
COPY --from=compress /usr/bin/caddy /bin/caddy
COPY --from=compress /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=compress /usr/bin/curl /bin/curl

# copy default caddyfile
COPY Caddyfile /etc/Caddyfile

# set default path for certs
VOLUME ["/etc/caddycerts"]
ENV CADDYPATH=/etc/caddycerts

# serve from /www
VOLUME ["/www"]
WORKDIR /www
COPY index.html /www/index.html

HEALTHCHECK --interval=25s --timeout=2s --start-period=15s CMD /bin/curl --fail http://localhost:9180/metrics || exit 1
CMD ["/bin/caddy", "--conf", "/etc/Caddyfile", "--log", "stdout", "-agree", "--root", "/www"]
