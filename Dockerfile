#
# Build stage by @abiosoft https://github.com/abiosoft/caddy-docker
#
FROM golang:1.12-alpine as build

ARG BUILD_DATE
ARG VCS_REF
ARG DEBIAN_FRONTEND=noninteractive

ARG caddy_version="v1.0.0"
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
RUN git clone https://github.com/dustin/go-humanize /go/src/github.com/dustin/go-humanize
RUN git clone https://github.com/gorilla/websocket /go/src/github.com/gorilla/websocket
RUN git clone https://github.com/jimstudt/http-authentication /go/src/github.com/jimstudt/http-authentication
RUN git clone https://github.com/naoina/toml /go/src/github.com/naoina/toml
RUN git clone https://github.com/naoina/go-stringutil /go/src/github.com/naoina/go-stringutil
RUN git clone https://github.com/VividCortex/ewma /go/src/github.com/VividCortex/ewma
RUN git clone https://github.com/cheekybits/genny /go/src/github.com/cheekybits/genny
RUN git clone https://github.com/marten-seemann/qpack /go/src/github.com/marten-seemann/qpack
RUN git clone https://github.com/marten-seemann/qtls /go/src/github.com/marten-seemann/qtls

# build with telemetry enabled
RUN cd /go/src/github.com/mholt/caddy/caddy \
    && sed -i 's/h2quic/http3/g' /go/src/github.com/mholt/caddy/caddyhttp/proxy/upstream_test.go \
    && sed -i 's/h2quic/http3/g' /go/src/github.com/mholt/caddy/caddyhttp/proxy/reverseproxy_test.go \
    && sed -i 's/h2quic/http3/g' /go/src/github.com/mholt/caddy/caddyhttp/proxy/proxy_test.go \
    && sed -i 's/h2quic/http3/g' /go/src/github.com/mholt/caddy/caddyhttp/proxy/reverseproxy.go \
    && sed -i 's/h2quic/http3/g' /go/src/github.com/mholt/caddy/caddyhttp/httpserver/server.go \
    && go install
    #&& mv caddy /go/bin

# test
RUN /go/bin/caddy -version
RUN /go/bin/caddy -plugins

#
# Compress Caddy with UPX
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

#
# Final image
#
FROM alpine:3.9.3

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-url="https://github.com/swarmstack/caddy.git" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.schema-version="1.0.0-rc1"

MAINTAINER Mike Holloway <mikeholloway+swarmstack@gmail.com>

# copy caddy binary and ca certs
COPY --from=compress /usr/bin/caddy /bin/caddy
COPY --from=compress /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# copy default caddyfile
COPY Caddyfile /etc/Caddyfile

# set default path for certs
VOLUME ["/etc/caddycerts"]
ENV CADDYPATH=/etc/caddycerts

# serve from /www
VOLUME ["/www"]
WORKDIR /www
COPY index.html /www/index.html

CMD ["/bin/caddy", "-conf", "/etc/Caddyfile", "-log", "stdout", "-agree", "-root", "/www"]
