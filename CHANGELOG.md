# Changelog

All notable changes to the four charts in this repository are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). All four charts (`core`, `sentinel`, `minion`, `opennms-stack`) are released together with a single chart `version` and the same `appVersion` (the OpenNMS Horizon release they were tested against).

## [Unreleased]

(no unreleased changes yet)

## [0.3.0] — 2026-05-22

### Added

- **`core`, `sentinel`** — new structured Postgres auth surface. `global.postgresql.auth` (and per-subchart equivalents) now exposes `superuserSecret.{name,userKey,passwordKey}` and `appSecret.{name,userKey,passwordKey}`. Each block defaults to the CNPG-shaped key names `username` / `password`; operators with non-CNPG Secrets override `userKey` / `passwordKey` per block. Existing 0.2.0 single-Secret users can keep their Secret and point both blocks at it with explicit overrides — see `opennms-stack/README.md` upgrade notes.
- **`core`, `sentinel`** — new `elasticsearch.enableForwarding` value (default `true`), rendered into `org.opennms.features.flows.persistence.elastic.cfg` as a first-class master switch.
- **`core`** — `elasticsearch` block gains `replicas`, `connTimeout`, `readTimeout` for parity with Sentinel's flow-persistence surface. New helpers `core.elasticsearchUrl` and `core.elasticsearchExistingSecret` resolve global → local so `global.elasticsearch.*` flows into Core when its optional flow-persistence path is enabled.
- **`opennms-stack`** — new `global.opennmsStack: true` marker. Sentinel uses this marker (rather than bare `.Values.global` truthiness) to detect the umbrella context and fall through to the Core-rendered lab-mode app Secret. Standalone Sentinel installs with unrelated `--set global.foo=bar` flags continue to fail-fast correctly.
- **`core`** — lab-mode renders two release-scoped Secrets — `<release>-opennms-pg-superuser` and `<release>-opennms-pg-app` — each shaped like CNPG (`username` / `password` keys). Sentinel under the umbrella synthesises the same name from `.Release.Name` alone, independent of Core's `nameOverride` / `fullnameOverride`. The two lab-mode renders are independent so operators can migrate one role at a time.

### Removed

- **`core`, `sentinel`, `opennms-stack`** — `postgresql.auth.existingSecret` removed from values, helpers (`core.postgresExistingSecret`, `core.postgresSecretName`, `sentinel.postgresExistingSecret`), templates, NOTES.txt, READMEs, and examples. The old single-Secret form is no longer accepted.
- **`core`** — `core/templates/core-credentials.yaml` deleted. Replaced by `core-pg-superuser-credentials.yaml` and `core-pg-app-credentials.yaml`, which each render a CNPG-shaped Secret only when its corresponding `<role>Secret.name` is empty.
- **`core`** — `envFrom: secretRef` removed from both `core-init` and runtime container in `statefulset.yaml`; replaced by four explicit `valueFrom.secretKeyRef` env entries emitted by the new `core.postgresEnv` helper.

### Changed

- **All four charts** — strict-pin cascade: `core`, `sentinel`, `opennms-stack` all bump from `0.2.0` to `0.3.0`. Umbrella `dependencies` strict-pin updated to `=0.3.0`. `minion` chart is unaffected by 0.3.0 changes; its version stays at `0.2.0`.

### Breaking changes (upgrade impact for 0.2.0 → 0.3.0 users)

- **`postgresql.auth.existingSecret` is removed.** Migration paths (see `opennms-stack/README.md` "Upgrading from 0.2.0"):
  - **CNPG users:** set `superuserSecret.name` and `appSecret.name` to the per-role Secrets your operator already generates. Defaults handle the `username`/`password` key names.
  - **Legacy single-Secret users:** keep your Secret. Point both blocks at it with explicit `userKey` / `passwordKey` overrides — see the README for the exact YAML.
- **`<release>-core-credentials` lab-mode Secret name is gone.** Anything that referenced the old name out-of-band (CI scripts, kubectl assertions) needs to point at `<release>-opennms-pg-superuser` and `<release>-opennms-pg-app` instead.
- **`envFrom` projection of the Postgres Secret is gone.** Operators who reused the 0.2.0 `existingSecret` to carry extra keys (e.g. shared Kafka/HTTP credentials) lose that side-projection — only the four expected Postgres env vars are now mounted.
- **Standalone Sentinel installs without `appSecret.name` fail at template time.** Under the umbrella, Sentinel falls through to Core's lab-mode app Secret automatically.

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

[Unreleased]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/labmonkeys-space/opennms-helm-charts/releases/tag/v0.1.0
