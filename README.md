# Typesense HA Sidecar

A lightweight DNS resolver sidecar container for Typesense High Availability (HA) deployments. This sidecar continuously resolves DNS hostnames and generates a node list file in the format required by Typesense's `--nodes` configuration, enabling dynamic cluster discovery in containerized environments.

## Purpose

In high availability Typesense deployments, nodes need to discover and communicate with each other. When deploying with orchestration platforms like Kubernetes, Docker Swarm, or other container orchestrators that provide DNS-based service discovery, node IP addresses can change dynamically.

This sidecar solves that problem by:
- Continuously resolving a DNS hostname (e.g., a Kubernetes headless service)
- Generating a Typesense-compatible node list file
- Updating the file as the cluster scales or IPs change
- Maintaining stability by keeping the last known good state if DNS resolution fails

## How It Works

The sidecar runs a simple shell script that:
1. Resolves the configured DNS hostname at regular intervals
2. Formats the discovered IPs into Typesense's node format: `ip1:peering_port:api_port,ip2:peering_port:api_port`
3. Writes the result to a shared volume that Typesense can read
4. Typesense uses this file with the `--nodes=$(cat /data/typesense-nodes)` flag

## Usage

### Docker Run

```bash
docker run -d \
  -v typesense-nodes:/data \
  -e HOSTNAME=typesense.default.svc.cluster.local \
  -e INTERVAL=10 \
  -e OUTFILE=/data/typesense-nodes \
  -e PEERING_PORT=8107 \
  -e API_PORT=8108 \
  -e IP_FAMILY=4 \
  ghcr.io/codingducksrl/typesense-ha-sidecar:latest
```

### Docker Compose

```yaml
version: '3.8'

services:
  typesense-resolver:
    image: ghcr.io/codingducksrl/typesense-ha-sidecar:latest
    environment:
      HOSTNAME: typesense-headless.default.svc.cluster.local
      INTERVAL: 10
      OUTFILE: /data/typesense-nodes
      PEERING_PORT: 8107
      API_PORT: 8108
      IP_FAMILY: 4
    volumes:
      - typesense-nodes:/data

  typesense:
    image: typesense/typesense:latest
    command: >
      --nodes=$(cat /data/typesense-nodes)
      --data-dir=/data/typesense
      --api-key=your-api-key
    volumes:
      - typesense-nodes:/data:ro
      - typesense-data:/data/typesense
    depends_on:
      - typesense-resolver

volumes:
  typesense-nodes:
  typesense-data:
```

### Kubernetes

```yaml
apiVersion: v1
kind: Service
metadata:
  name: typesense-headless
spec:
  clusterIP: None
  selector:
    app: typesense
  ports:
    - name: peering
      port: 8107
    - name: api
      port: 8108
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: typesense
spec:
  serviceName: typesense-headless
  replicas: 3
  selector:
    matchLabels:
      app: typesense
  template:
    metadata:
      labels:
        app: typesense
    spec:
      containers:
        - name: resolver
          image: ghcr.io/codingducksrl/typesense-ha-sidecar:latest
          env:
            - name: HOSTNAME
              value: "typesense-headless.default.svc.cluster.local"
            - name: INTERVAL
              value: "10"
            - name: OUTFILE
              value: "/data/typesense-nodes"
            - name: PEERING_PORT
              value: "8107"
            - name: API_PORT
              value: "8108"
            - name: IP_FAMILY
              value: "4"
          volumeMounts:
            - name: shared-data
              mountPath: /data
        
        - name: typesense
          image: typesense/typesense:latest
          command:
            - /bin/sh
            - -c
            - |
              sleep 5  # Wait for resolver to create the nodes file
              /opt/typesense-server \
                --nodes=$(cat /data/typesense-nodes) \
                --data-dir=/data/typesense \
                --api-key=${TYPESENSE_API_KEY}
          env:
            - name: TYPESENSE_API_KEY
              valueFrom:
                secretKeyRef:
                  name: typesense-secret
                  key: api-key
          volumeMounts:
            - name: shared-data
              mountPath: /data
              readOnly: true
            - name: typesense-data
              mountPath: /data/typesense
          ports:
            - containerPort: 8107
              name: peering
            - containerPort: 8108
              name: api
      
      volumes:
        - name: shared-data
          emptyDir: {}
  
  volumeClaimTemplates:
    - metadata:
        name: typesense-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```

## Environment Variables

All configuration is done through environment variables:

### `HOSTNAME` (required)

The DNS hostname to resolve. This should be a DNS name that resolves to all Typesense nodes in your cluster.

- **Required:** Yes
- **Default:** `example.com` (placeholder in Dockerfile - **must be overridden** for the sidecar to function properly)
- **Example:** `typesense.default.svc.cluster.local`

⚠️ **Important:** The default value `example.com` is not functional and must be replaced with your actual service DNS name.

In Kubernetes, this is typically a headless service name. In Docker Swarm, this would be a service name.

### `INTERVAL`

The interval (in seconds) between DNS resolution attempts.

- **Required:** No
- **Default:** `10`
- **Example:** `30`

Lower values provide faster updates when nodes are added/removed, but increase DNS query load. Higher values reduce load but slow down cluster updates.

### `OUTFILE`

The path where the node list file will be written. This should be on a shared volume that Typesense can read.

- **Required:** No
- **Default:** `/data/ips.txt` (Dockerfile ENV overrides the script's default of `/data/typesense-nodes`)
- **Example:** `/data/typesense-nodes`, `/shared/nodes.txt`

The file contains a comma-separated list in Typesense's node format: `ip1:peering_port:api_port,ip2:peering_port:api_port`

### `PEERING_PORT`

The port that Typesense uses for cluster peering/replication.

- **Required:** No
- **Default:** `8107`
- **Example:** `8107`

This is Typesense's default peering port. Change it if you've configured Typesense to use a different port.

### `API_PORT`

The port that Typesense uses for the API.

- **Required:** No
- **Default:** `8108`
- **Example:** `8108`

This is Typesense's default API port. Change it if you've configured Typesense to use a different port.

### `IP_FAMILY`

The IP address family to resolve.

- **Required:** No
- **Default:** `4`
- **Allowed values:** `4`, `6`, `both`
- **Example:** `both`

- `4`: Resolve only IPv4 addresses (A records)
- `6`: Resolve only IPv6 addresses (AAAA records)
- `both`: Resolve both IPv4 and IPv6 addresses

## Output Format

The sidecar generates a file containing a comma-separated list of nodes in the format:

```
10.0.1.1:8107:8108,10.0.1.2:8107:8108,10.0.1.3:8107:8108
```

This format is directly compatible with Typesense's `--nodes` configuration parameter.

## Error Handling

If DNS resolution fails or returns no results, the sidecar:
- Logs a warning message
- Keeps the existing node list file unchanged
- Continues attempting to resolve at the configured interval

This ensures that temporary DNS issues don't break an existing cluster by removing all nodes.

## Requirements

- Docker or a compatible container runtime
- A DNS service that resolves to your Typesense nodes
- A shared volume between the sidecar and Typesense containers

## Building

The image is automatically built and published to GitHub Container Registry when a release is created. To build manually:

```bash
docker build -t typesense-ha-sidecar:local .
```

## Multi-Architecture Support

The published images support multiple architectures:
- `linux/amd64`
- `linux/arm64`

## License

This project is provided as-is for use with Typesense deployments.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Related Links

- [Typesense Documentation](https://typesense.org/docs/)
- [Typesense Clustering Guide](https://typesense.org/docs/guide/high-availability.html)
