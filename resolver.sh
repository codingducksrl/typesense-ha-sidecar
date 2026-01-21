#!/bin/sh
set -eu

: "${HOSTNAME:?HOSTNAME is required (the DNS name to resolve)}"
: "${INTERVAL:=10}"
: "${OUTFILE:=/data/typesense-nodes}"
: "${PEERING_PORT:=8107}"
: "${API_PORT:=8108}"
: "${IP_FAMILY:=4}"   # 4 | 6 | both

mkdir -p "$(dirname "$OUTFILE")"

echo "Resolving $HOSTNAME every ${INTERVAL}s -> $OUTFILE (Typesense --nodes format)" >&2

dig_ips() {
  case "$IP_FAMILY" in
    4)    dig +short A "$HOSTNAME" ;;
    6)    dig +short AAAA "$HOSTNAME" ;;
    both) { dig +short A "$HOSTNAME"; dig +short AAAA "$HOSTNAME"; } ;;
    *)    echo "IP_FAMILY must be 4, 6, or both (got: $IP_FAMILY)" >&2; exit 1 ;;
  esac
}

while true; do
  tmp="$(mktemp)"

  ips="$(dig_ips 2>/dev/null | sed '/^$/d' | sort -u || true)"

  # If DNS fails / returns nothing, keep the existing file to avoid breaking the cluster.
  if [ -z "${ips:-}" ]; then
    echo "Warning: no IPs resolved for $HOSTNAME, keeping existing $OUTFILE" >&2
    rm -f "$tmp"
    sleep "$INTERVAL"
    continue
  fi

  # Format: ip:peering_port:api_port,ip2:peering_port:api_port
  nodes="$(
    printf '%s\n' "$ips" \
      | awk -v pp="$PEERING_PORT" -v ap="$API_PORT" '{print $1 ":" pp ":" ap}' \
      | paste -sd, -
  )"

  printf '%s\n' "$nodes" > "$tmp"
  mv "$tmp" "$OUTFILE"

  sleep "$INTERVAL"
done
