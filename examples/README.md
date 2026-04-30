# Example values files

Working `values.yaml` recipes for common deployment scenarios. Each file is
self-contained — you can `helm install ... -f <file>` against the published
chart repo or OCI artifacts.

## Available examples

| File                                          | Chart            | Scenario                                                           |
| --------------------------------------------- | ---------------- | ------------------------------------------------------------------ |
| [`opennms-stack-prod-byo.yaml`](opennms-stack-prod-byo.yaml)         | `opennms-stack`  | Production-style central-site install with all credentials provided via `existingSecret` references |
| [`opennms-stack-with-prometheus.yaml`](opennms-stack-with-prometheus.yaml) | `opennms-stack`  | Same as above plus the `prometheus-remote-writer` plugin pointing at a Mimir/Cortex/VictoriaMetrics backend |
| [`minion-remote-location.yaml`](minion-remote-location.yaml)         | `minion`         | A Minion deployed to a remote site, talking to a central OpenNMS over BYO Kafka |

## Using an example

```bash
helm repo add opennms-helm-charts https://labmonkeys-space.github.io/opennms-helm-charts/
helm repo update

# Pages-served chart repo
helm install onms opennms-helm-charts/opennms-stack \
  -f examples/opennms-stack-prod-byo.yaml \
  --version 0.1.0

# OCI registry
helm install onms oci://ghcr.io/labmonkeys-space/charts/opennms-stack \
  -f examples/opennms-stack-prod-byo.yaml \
  --version 0.1.0
```

## Before installing

Each example assumes the underlying infrastructure already exists (BYO):

- A reachable PostgreSQL cluster (with the OpenNMS DB user pre-created).
- A reachable Apache Kafka cluster (PLAINTEXT or SASL — the examples document which).
- A reachable Elasticsearch cluster (for Sentinel flow persistence — only the stack examples).
- The Kubernetes Secrets the examples reference, created out-of-band in the same namespace as the release. Each example's header comments list the expected Secret keys.

Need a quick-start without managing infrastructure? See the in-repo `make dev-install-stack` target — it bootstraps a kind cluster with throwaway Postgres/Kafka/Elasticsearch stubs from `stubs/`. Strictly for local development, not production.
