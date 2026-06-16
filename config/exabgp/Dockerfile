FROM python:3.12-slim-trixie

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

COPY exabgp.conf /etc/exabgp/exabgp.conf
COPY exabgp.env /etc/exabgp/exabgp.env

COPY flowspec-api.py /usr/local/bin/flowspec-api.py
RUN chmod +x /usr/local/bin/flowspec-api.py

RUN mkfifo /run/exabgp.in && \
    chmod 666 /run/exabgp.in && \
    mkfifo /run/exabgp.out && \
    chmod 666 /run/exabgp.out && \
    mkfifo /var/run/exabgp.cmd && \
    chmod 777 /var/run/exabgp.cmd

RUN uv tool install "exabgp==4.2.25"

CMD ["/root/.local/bin/exabgp", "/etc/exabgp/exabgp.conf"]
