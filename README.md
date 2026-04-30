[![lint and test](https://github.com/labmonkeys-space/opennms-helm-charts/actions/workflows/lint-and-test.yaml/badge.svg?branch=main)](https://github.com/labmonkeys-space/opennms-helm-charts/actions/workflows/lint-and-test.yaml)

## Helm Charts for OpenNMS

Helm charts for deploying [OpenNMS Horizon](https://www.opennms.com/horizon/) on Kubernetes against externally-managed Postgres, Kafka, and Elasticsearch clusters. The charts configure connectivity to those systems; they do **not** deploy them.

### Which chart should I install?

| Use case                                            | Chart            | Workload           |
| --------------------------------------------------- | ---------------- | ------------------ |
| Central OpenNMS site (Core + Sentinel together)     | `opennms-stack`  | StatefulSet + Deployment |
| Just the Core component (admin UI, alarm engine)    | `core`           | StatefulSet (replicas: 1) |
| Just Sentinel (extra flow processors at the central site) | `sentinel`       | Deployment (HPA-able) |
| Minion at a remote location, *one release per site* | `minion`         | StatefulSet (per-pod identity) |

The `opennms-stack` umbrella strict-pins matched versions of `core` and `sentinel`. Minion is deployed independently — typically once per remote location — and is **not** part of the umbrella.

### BYO infrastructure

You bring:

- **PostgreSQL** — Core writes events/nodes/alarms here; Sentinel reads/writes the same database.
- **Apache Kafka** — IPC between Core, Sentinel, and Minions. Apache Kafka only; ActiveMQ and other JMS strategies are not supported.
- **Elasticsearch** — flow persistence target for Sentinel.

The charts reference Kubernetes Secrets you manage out-of-band for credentials. See each chart's README for the expected Secret keys.

### Versioning

`appVersion` in each chart's `Chart.yaml` reflects the OpenNMS Horizon release the chart was tested against (currently `35.0.5`). Core, Minion, and Sentinel are released together by upstream and **share** the version number — `appVersion` ratchets across all four charts in lock-step.

The `opennms-stack` umbrella strict-pins exact `core` and `sentinel` chart versions in its `dependencies`. Bumping a subchart bumps the umbrella's `version`.

Image tags default to `""` and fall through to `.Chart.AppVersion` at template time. Override with `--set image.tag=bleeding` for development.

### Time-series strategy

Default: **RRDtool** writing to a chart-managed PVC at `/opennms-data/rrd`.

For BYO Prometheus-compatible time-series storage (Cortex, Mimir, VictoriaMetrics, Thanos, Prometheus with `--enable-feature=remote-write-receiver`), set `prometheusRemoteWriter.enabled=true` on the Core chart. The chart downloads the [`opennms-forge/prometheus-remote-writer`](https://github.com/opennms-forge/prometheus-remote-writer) plugin at pod start and configures it.

Newts/Cassandra is not supported.

### Local development

```bash
make help                   # show all targets
make lint                   # ct lint all four charts
make kind-create            # spin up a local kind cluster
make test-install-core      # install Core against in-cluster CNPG Postgres
make test-install-sentinel  # install Sentinel
make test-install-minion    # install Minion (no infra needed)
make test-install-stack     # install the opennms-stack umbrella with
                            # CNPG Postgres + Kafka + Elasticsearch stubs
make readme                 # regenerate per-chart README.md via helm-docs
make kind-delete            # tear down the kind cluster
```

The `stubs/` directory holds throwaway manifests for chart-testing only: a CNPG-managed Postgres cluster, a single-pod Apache Kafka, and a single-pod Elasticsearch. None of these are production-ready.

### Repository layout

```
charts/
  core/                OpenNMS Horizon Core chart (StatefulSet + PVC)
  sentinel/            OpenNMS Sentinel chart (Deployment + HPA-able)
  minion/              OpenNMS Minion chart (StatefulSet, per-pod identity)
  opennms-stack/       umbrella over core + sentinel
stubs/
  postgres/            CNPG manifests for chart-testing
  kafka/               single-pod Kafka in KRaft mode
  elasticsearch/       single-pod Elasticsearch
.github/workflows/
  lint-and-test.yaml   CI: ct lint + ct install for all four charts
openspec/              change proposals and specs (see openspec/AGENTS.md)
```

### Examples

Working `values.yaml` recipes for common scenarios (production BYO, Mimir-backed time-series, edge Minion) live under [`examples/`](examples/).

### Changelog

See [`CHANGELOG.md`](CHANGELOG.md) for the per-release contract.

### Releasing

Maintainers cut releases by pushing a `v*` tag on `main`. See [`RELEASING.md`](RELEASING.md) for the full operator playbook (release-PR checklist, tag procedure, first-time repo bootstrap, yanking).

### License

Apache License 2.0 — see [`LICENSE`](LICENSE).
