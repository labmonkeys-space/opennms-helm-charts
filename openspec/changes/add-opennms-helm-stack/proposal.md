## Why

This repository hosts Helm charts that today are an unfinished mix of OpenNMS-Core scaffolding and vanilla `helm create` boilerplate (Minion and Sentinel ship with `nginx` images and no OpenNMS-specific wiring). To deploy OpenNMS Horizon on Kubernetes against existing infrastructure (Postgres, Kafka, Elasticsearch) the user needs a coherent set of charts that configure connectivity to those external systems and nothing else — no infra is deployed by these charts. The latest stable Horizon is 35.0.5; Core, Minion, and Sentinel are released together and share the version number.

## What Changes

- Establish three component charts (`core`, `sentinel`, `minion`) and one umbrella (`opennms-stack`) over `core` + `sentinel`. Minion is independent of the umbrella.
- Replace the existing Minion and Sentinel `helm create` scaffolds with real OpenNMS deployments using the `opennms/minion` and `opennms/sentinel` images.
- Adopt an env-vars-first configuration model with a Helm-templated etc-overlay for anything not exposed as a direct env var. Confd remains in the upstream image but is deliberately left inert (mounted-but-empty config YAML).
- Restrict the messaging broker to **Apache Kafka only**. ActiveMQ and other JMS strategies are out of scope.
- Time-series strategy defaults to **RRDtool** (the OpenNMS default). The chart additionally supports **BYO Prometheus-compatible backend** (Cortex, Mimir, VictoriaMetrics, Thanos, Prometheus with remote-write-receiver) via the [`opennms-forge/prometheus-remote-writer`](https://github.com/opennms-forge/prometheus-remote-writer) plugin: the chart downloads the published KAR into the OpenNMS overlay directory at pod start and renders the required `.cfg` + `timeseries.properties` files. **Newts/Cassandra is explicitly out of scope** and not modelled at any level.
- For `.cfg` files mixing non-secret config and secret values, render a ConfigMap template + reference a Secret + run an `envsubst` initContainer that writes the final file to an `emptyDir` mounted as the etc-overlay (Option 2 pattern).
- Switch Minion from Deployment+HPA (current scaffold) to a **StatefulSet** (`replicas: 1` default, no HPA, per-replica PVC). Inject `MINION_ID` from `metadata.name` via the downward API.
- Add a single **PVC at `/opennms-data`** for Core (default 50Gi); Karaf data and logs remain ephemeral.
- Upgrade Core liveness from `pgrep java` to `tcpSocket` on the webui port; keep `/opennms/login.jsp` readiness for v1.
- Keep Core's install/upgrade as an **initContainer** in v1 (defer Helm-Job migration).
- Pin `opennms-stack`'s subchart dependencies on `core` and `sentinel` with **strict-pin** versions.
- Set `appVersion: "35.0.5"` lock-step across all three charts; default `image.tag` to empty so it falls through to `.Chart.AppVersion`.
- Sentinel ships only as part of `opennms-stack` (no edge-Sentinel pattern).

## Capabilities

### New Capabilities

- `core-chart`: Helm chart that deploys OpenNMS Horizon Core against an external Postgres database, an external Kafka cluster, and an optional external Elasticsearch.
- `sentinel-chart`: Helm chart that deploys OpenNMS Sentinel against an external Postgres, Kafka, and Elasticsearch. Installable standalone or as a subchart of `opennms-stack`.
- `minion-chart`: Helm chart that deploys OpenNMS Minion against an external Kafka cluster, with stable per-pod identity and per-replica persistent state. Installable standalone only.
- `opennms-stack-chart`: Umbrella Helm chart bundling `core` and `sentinel` with strict-pinned subchart versions for matched-pair install and upgrade.

### Modified Capabilities

(none — repository has no prior published specs)

## Impact

- **Charts**: significant rewrite of `charts/minion` and `charts/sentinel`; targeted edits and additions to `charts/core`; new `charts/opennms-stack` directory.
- **Test infra**: `stubs/postgres/` (CNPG) stays as testing-only scaffolding; the Makefile targets that depend on it (`test-install-core`, `test-install-sentinel`) remain valid.
- **CI**: lint-and-test workflow extends to cover the new umbrella and the rewritten Minion/Sentinel charts.
- **Documentation**: helm-docs regenerates `README.md` in each chart; the top-level `README.md` adds an installation matrix (which chart for which use case).
- **Versioning policy**: chart `appVersion` ratchets in lock-step with OpenNMS releases; chart `version` follows independent semver per chart, with `opennms-stack` bumping whenever its strict-pinned dependencies bump.
- **Out of scope (v2 follow-ups)**: `/opennms/rest/health` healthcheck w/ auth, schema-driven values.yaml generation. Newts/Cassandra time-series support is permanently out of scope (use the prometheus-remote-writer integration instead).
