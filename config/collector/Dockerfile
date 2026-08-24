FROM alpine:latest

RUN apk update && apk add --no-cache tcpdump

RUN wget https://github.com/meirdev/rustflow/releases/download/v0.10.0/rustflow && \
    chmod +x rustflow && \
    mv rustflow /usr/local/bin/
