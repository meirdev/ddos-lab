FROM alpine:latest

RUN apk add --no-cache \
        tcpdump \
        curl \
        nftables \
        python3

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN set -eux; \
    curl -fsSL -o /usr/local/bin/rping \
        https://github.com/meirdev/rping/releases/download/v0.6.0/rping; \
    curl -fsSL -o /usr/local/bin/flowspecd \
        https://github.com/meirdev/flowspecd/releases/download/v0.1.0-dev/flowspecd; \
    curl -fsSL -o /usr/local/bin/rustflow \
        https://github.com/meirdev/rustflow/releases/download/v0.14.0/rustflow; \
    chmod +x /usr/local/bin/rping /usr/local/bin/flowspecd /usr/local/bin/rustflow; \
    curl -fsSL -o /tmp/node_exporter.tar.gz \
        https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz; \
    tar xzf /tmp/node_exporter.tar.gz -C /tmp; \
    mv /tmp/node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/; \
    rm -rf /tmp/node_exporter*

RUN uv tool install "exabgp==4.2.25"
ENV PATH="/root/.local/bin:${PATH}"

COPY exabgp/exabgp.conf /etc/exabgp/exabgp.conf
COPY exabgp/exabgp.env /etc/exabgp/exabgp.env
COPY exabgp/flowspec-api.py /usr/local/bin/flowspec-api.py
RUN chmod +x /usr/local/bin/flowspec-api.py

RUN mkfifo /run/exabgp.in  && chmod 666 /run/exabgp.in  && \
    mkfifo /run/exabgp.out && chmod 666 /run/exabgp.out && \
    mkfifo /var/run/exabgp.cmd && chmod 777 /var/run/exabgp.cmd

CMD ["tail", "-f", "/dev/null"]
