FROM alpine:latest

RUN apk update && apk add --no-cache tcpdump

RUN wget https://github.com/meirdev/rustflow/releases/download/v0.6.0/rustflow_collector && \
    chmod +x rustflow_collector && \
    mv rustflow_collector /usr/local/bin/
