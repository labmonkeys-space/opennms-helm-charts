# Changelog

All notable changes to the four charts in this repository are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). All four charts (`core`, `sentinel`, `minion`, `opennms-stack`) are released together with a single chart `version` and the same `appVersion` (the OpenNMS Horizon release they were tested against).

## [Unreleased]

(no unreleased changes yet)

## [0.2.0] — 2026-05-07

### Added

- **`core`** — when `kafka.bootstrapServers` is set, the chart now auto-emits the full Kafka-IPC scaffolding into the etc-overlay: `opennms.properties.d/disable-activemq.properties` (sets `org.opennms.activemq.broker.disable=true`) and `featuresBoot.d/kafka-{ipc,rpc,sink,twin}.boot` (disable JMS IPC features, enable Kafka). Mirrors what the `minion` chart has done since 0.1.0. Removes the manual-`extraConfigFiles` boilerplate previously needed to put a Kafka-only Core into a working state.

### Removed

- **`sentinel`, `minion`** — removed `opennms.broker.existingSecret` from values, templates (`OPENNMS_BROKER_USER/PASS` env injection), `NOTES.txt`, READMEs, and example files. The chart has been Apache-Kafka-only since 0.1.0 (per the top-level README); the broker-secret wiring was vestigial — Sentinel and Minion only use `opennms.http.existingSecret` to authenticate to Core's REST API. Existing values files with `opennms.broker:` set will be silently ignored (Helm does not enforce the values schema).
- **`opennms-stack`** — removed `sentinel.opennms.broker.*` references from `NOTES.txt` and the two umbrella examples (`examples/opennms-stack-prod-byo.yaml`, `examples/opennms-stack-with-prometheus.yaml`).

### Changed

- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, and `opennms-stack` all bump from `0.1.0` to `0.2.0`. Umbrella `Chart.lock` regenerated.

### Breaking changes (upgrade impact for 0.1.0 → 0.2.0 users)

- **`core` — embedded ActiveMQ broker no longer listens on port 61616 when `kafka.bootstrapServers` is set.** The new `disable-activemq.properties` overlay file sets `org.opennms.activemq.broker.disable=true`, so any north-bound JMS integrations or external ActiveMQ consumers pointing at the in-pod broker will lose their listener on upgrade. Operators who require both Kafka IPC *and* the embedded broker (e.g., during a JMS-to-Kafka migration) can override the file via `extraConfigFiles."opennms.properties.d/disable-activemq.properties": ""`.
- **`sentinel`, `minion` — broker-only credential users silently drop from `-c` to `-f` startup mode.** The startup-arg gate previously fired on `or http broker`; it now fires on `http` alone. Users who supplied ONLY `opennms.broker.existingSecret` (no `opennms.http.existingSecret`) were registering with Core via the SCV keystore on 0.1.0 and will fall to `-f` (no SCV registration / lab mode) on 0.2.0. Set `opennms.http.existingSecret` to restore `-c` mode.

[0.2.0]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.1.0...v0.2.0

## [0.1.0] — 2026-04-30

First published release of the OpenNMS Helm Charts.

### Added

- **`core`** chart — OpenNMS Horizon Core deployed as a single-replica StatefulSet. Connects to BYO Postgres via env vars and (optionally) BYO Kafka and Elasticsearch via a Helm-templated etc-overlay. Single 50Gi PVC at `/opennms-data` for RRD time-series, MIBs, and reports. `tcpSocket` liveness on the WebUI port; `/opennms/login.jsp` readiness. Optional [`opennms-forge/prometheus-remote-writer`](https://github.com/opennms-forge/prometheus-remote-writer) integration that downloads the KAR plugin into `/opt/opennms-overlay/deploy` at pod start and switches the time-series strategy to `integration`.
- **`sentinel`** chart — OpenNMS Sentinel deployed as a `Deployment` with optional HPA. Connects to BYO Postgres (distributed datasource), Kafka (sink), and Elasticsearch (flow persistence). Karaf shell on port 8301; no public HTTP surface.
- **`minion`** chart — OpenNMS Minion deployed as a StatefulSet with stable per-pod identity (`MINION_ID` from `metadata.name` via the downward API). Per-replica PVC for Karaf state. Apache Kafka only as the IPC strategy — `kafka-*.boot` files in the etc-overlay swap the JMS feature set for the Kafka equivalents. `sshHost=0.0.0.0` override so the Service-routed health checks reach the Karaf shell port.
- **`opennms-stack`** chart — Umbrella over `core` and `sentinel` for the central OpenNMS site. Strict-pinned subchart versions enforce the matched-pair invariant (Core and Sentinel must run the same OpenNMS major). Shared `global.*` values flow into both subcharts.
- BYO infrastructure model — none of the charts deploy Postgres, Kafka, or Elasticsearch. Users provide endpoints + credentials via referenced Kubernetes Secrets.
- Tag-triggered release pipeline publishing to **GitHub Pages** (Helm repo at `https://labmonkeys-space.github.io/opennms-helm-charts/`) and **GHCR** (OCI artifacts at `ghcr.io/labmonkeys-space/charts/<chart>`). See `RELEASING.md` for the operator playbook.
- Chart-testing matrix in CI — `lint`, `helm-docs`, and four parallel `test-install-*` jobs (one per chart) on every push and pull request.
- Dependabot configuration for weekly GitHub Actions SHA-pin updates.

### Compatibility

- **OpenNMS Horizon** `35.0.5` (`appVersion`).
- **Kubernetes** 1.27+ (tested against 1.34 in CI via kind).
- **Helm** 3.13+ (3.8+ required for OCI install).

### Known limitations

- `core.postgresql.host` defaults to a CNPG-specific hostname (`cluster-helm-lint-rw.default.svc.cluster.local`) used by the in-repo chart-testing flow. Production users must set `postgresql.host` explicitly — the chart fails template-time on missing host.
- The optional `prometheus-remote-writer` plugin is downloaded from GitHub Releases at every pod start when enabled. Air-gapped clusters override `prometheusRemoteWriter.kar.url` to an internal mirror.

[Unreleased]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.2.0...HEAD
[0.1.0]: https://github.com/labmonkeys-space/opennms-helm-charts/releases/tag/v0.1.0
