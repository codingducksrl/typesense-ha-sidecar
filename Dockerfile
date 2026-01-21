FROM alpine:3.23.2

RUN apk add --no-cache bind-tools

WORKDIR /app
COPY resolver.sh /app/resolver.sh
RUN chmod +x /app/resolver.sh

# Defaults (override with env vars)
ENV HOSTNAME=example.com
ENV INTERVAL=10
ENV OUTFILE=/data/ips.txt
ENV PEERING_PORT=8107
ENV API_PORT=8108
ENV IP_FAMILY=4

VOLUME ["/data"]

CMD ["/app/resolver.sh"]
