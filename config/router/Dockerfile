FROM alpine:latest

RUN apk update && apk add --no-cache nftables tcpdump

RUN wget https://github.com/meirdev/flowspecd/releases/download/v0.1.0-dev/flowspecd && \
    chmod +x flowspecd && \
    mv flowspecd /usr/local/bin/

RUN wget https://github.com/meirdev/rustflow/releases/download/v0.10.0/rustflow && \
    chmod +x rustflow && \
    mv rustflow /usr/local/bin/

RUN wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz && \
    tar xvfz node_exporter-1.10.2.linux-amd64.tar.gz && \
    mv node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/ && \
    rm -rf node_exporter-1.10.2.linux-amd64*
