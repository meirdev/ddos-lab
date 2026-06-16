FROM alpine:latest

RUN apk update && apk add --no-cache tcpdump curl && \
    curl -L -O https://github.com/meirdev/rping/releases/download/v0.3.0/rping && \
    chmod +x rping && \
    mv rping /usr/local/bin/
