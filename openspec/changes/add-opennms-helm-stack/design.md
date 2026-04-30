## Context

OpenNMS Horizon is a network management platform whose deployable units are three Java/Karaf-based components:

- **Core** — central web UI, scheduler, alarm/event engine. One per environment.
- **Sentinel** — distributed flow processor. Co-located with Core; horizontally scaled with flow load.
- **Minion** — edge collector. Deployed *per remote location*, often into separate Kubernetes clusters owned by separate teams.

The container images are published to Docker Hub (`opennms/horizon`, `opennms/sentinel`, `opennms/minion`) and built from `OpenNMS/opennms` at `opennms-container/`. They consume configuration through three channels in this order at container start:

1. **Direct env vars** (consumed by the entrypoint script and the Java installer)
2. **Confd templates** rendered from a YAML overlay file (file backend, not env backend) into Karaf `.cfg` files
3. **Etc-overlay** (`rsync` of any files placed in `/opt/<comp>-etc-overlay/` into `etc/`)

The order is significant: confd runs first, then etc-overlay overwrites whatever confd produced. So files written via the etc-overlay always win.

Repository state at the start of this change:
- `charts/core/` — partially complete: StatefulSet + ConfigMap + Secret + Postgres env-var wiring; no Kafka, no Elasticsearch, no PVC.
- `charts/minion/`, `charts/sentinel/` — vanilla `helm create` scaffolding with `nginx` images and no OpenNMS-specific configuration.
- `stubs/postgres/` — CNPG manifests, used only by `make test-install-*` to provide a Postgres for chart-testing.

External constraints:
- Postgres, Kafka, and Elasticsearch are **bring-your-own**. The charts configure connectivity to them; they never deploy them.
- Apache Kafka is the only supported messaging broker (no ActiveMQ).
- Latest stable Horizon is 35.0.5; Core, Sentinel, and Minion are released together and share that version.

## Goals / Non-Goals

**Goals:**

- Deploy OpenNMS Core + Sentinel as a single, opinionated Helm release (`opennms-stack`) for the central site.
- Deploy OpenNMS Minion as an independent Helm release per remote location, repeatable N times.
- Configure all three components to connect to BYO Postgres, Kafka, and Elasticsearch via clean values.yaml schemas backed by referenced Secrets for credentials.
- Keep the configuration surface explicit and Helm-templated; do not rely on the upstream confd mechanism for chart-managed config.
- Ship images locked to a tested Horizon version (35.0.5) by default, override-able for development.

**Non-Goals:**

- Deploying Postgres, Kafka, Elasticsearch, or any other infrastructure these charts depend on.
- Supporting ActiveMQ, JMS, or any messaging broker other than Apache Kafka.
- Supporting Newts/Cassandra time-series persistence — permanently out of scope (the prometheus-remote-writer integration covers the BYO time-series use case).
- Supporting authenticated `/opennms/rest/health` Kubernetes probes (deferred; v1 uses `tcpSocket` liveness + `login.jsp` readiness for Core).
- Supporting an "edge Sentinel" deployment topology.
- Generating values.yaml entries from upstream `minion-config-schema.yml` automatically.
- Replacing Core's install/upgrade `initContainer` with a Helm-managed Job.

## Decisions

### Decision 1: Topology — server umbrella + standalone Minion (Shape C)

Core+Sentinel deploy together at the central site. Minion deploys separately, often *N times across N sites*. The chart layout encodes this asymmetry:

```
charts/
  core/                 installable standalone, also subchart of opennms-stack
  sentinel/             installable standalone, also subchart of opennms-stack
  opennms-stack/        umbrella over core + sentinel
  minion/               independent — never an umbrella subchart
```

**Alternatives considered:**

- *Three independent charts (no umbrella).* Forces users co-deploying Core+Sentinel to maintain duplicated values (`postgresql.host`, `kafka.bootstrapServers`, `elasticsearch.url`) in two release values files. Rejected.
- *One umbrella over all three.* Misleads users into thinking Minion belongs at the central site, contradicts the per-location Minion lifecycle. Rejected.
- *Single mega-chart with `core.enabled` / `minion.enabled` / `sentinel.enabled` toggles.* Conditional-everywhere templates age badly; impossible to version components independently. Rejected.

### Decision 2: Umbrella name — `opennms-stack`

The umbrella is named `opennms-stack`, not the bare `stack` (too generic in `helm list`, ArtifactHub displays, sub-chart caches) and not `opennms-server` (Sentinel is not a server). The component charts keep their proper-noun names (`core`, `sentinel`, `minion`) since those are recognizable OpenNMS terms.

### Decision 3: Configuration channels — env vars first, etc-overlay second, confd inert

Configuration values are passed to the container via, in order of preference:

1. **Direct environment variables** on the container (from values, ConfigMaps, or Secrets).
2. **Etc-overlay**: Helm-templated `.cfg` / `.properties` files mounted into `/opt/<comp>-etc-overlay/`, where the entrypoint's `applyOverlayConfig` rsyncs them into `etc/` *after* confd has run.
3. **Confd YAML overlay**: deliberately mounted as `{}` (an empty object) so confd's `file` backend has a valid file but produces empty/default `.cfg` outputs that the etc-overlay then overwrites.

**Why not confd YAML?** Confd is a second templating engine on top of Helm; using both means the same value can be set in two places with non-obvious precedence. By rendering the final `.cfg` files in Helm and using the etc-overlay, the chart becomes the single source of truth for configuration.

**Cost accepted:** the chart owns knowledge of Karaf `.cfg` file shapes and must follow upstream changes to those shapes. The shapes have been stable for years and changes are infrequent.

### Decision 4: Messaging broker — Apache Kafka only

The chart only models and configures Kafka as the IPC broker between Core, Sentinel, and Minion. ActiveMQ and JMS are not exposed in any values schema. The Kafka boot files in Minion's confd templates (`kafka-ipc.boot`, `kafka-rpc.boot`, `kafka-sink.boot`, `kafka-twin.boot`) are written unconditionally into the etc-overlay.

Three Kafka concerns are configured per component, all pointing at the same brokers:

- **Sink** (`org.opennms.core.ipc.sink.kafka.cfg`) — Minion → Core/Sentinel events, syslog, traps, flows.
- **RPC** (`org.opennms.core.ipc.rpc.kafka.cfg`) — Core ↔ Minion request/response.
- **Twin** (`org.opennms.core.ipc.twin.kafka.cfg`) — Core → Minion config-sync.

A separate `instance-id.properties` file (with key `org.opennms.instance.id`, default `OpenNMS`) sets the queue/topic prefix that all three components share.

### Decision 5: Mixed-content `.cfg` pattern — Option 2 (envsubst initContainer)

Some `.cfg` files mix non-secret config (Kafka brokers, ES URL) with secret values (Postgres password, Kafka SASL password). To keep BYO `existingSecret` references clean and to remain compatible with `helm template` / dry-run / ArgoCD diffing, the chart uses:

```
ConfigMap (template with ${PLACEHOLDERS})  ┐
                                            ├─► initContainer ──► emptyDir ──► etc-overlay
Secret (referenced credentials as env vars)┘   (envsubst)
```

The init container runs `envsubst` over the templated `.cfg` files, substituting environment variables sourced from the Secret, and writes the final files to an `emptyDir` mounted at `/opt/<comp>-etc-overlay/etc/`. The runtime container never sees the placeholder file.

**Alternatives considered:**

- *Option 1: render the whole `.cfg` into a Secret using Helm `lookup`.* Fails in `helm template`, `--dry-run`, and ArgoCD diffing (lookup returns nothing in those modes). Also breaks BYO `existingSecret` semantics — copying contents out of an existing Secret defeats the purpose of having it. Rejected.
- *Karaf `${env:VAR}` substitution.* OpenNMS uses ConfigAdmin inconsistently; not all `.cfg` consumers resolve env vars, and verifying per-file is brittle. Rejected.

**Cost accepted:** one extra container per pod (~5MB Alpine image with `gettext` for `envsubst`, ~50ms startup overhead). Worth it for correctness across templating modes.

### Decision 6: Minion identity — downward API + envsubst

`MINION_ID` and `MINION_LOCATION` are required to be unique-per-pod and stable across reschedules. The chart injects them via:

```yaml
env:
  - name: MINION_ID
    valueFrom:
      fieldRef:
        fieldPath: metadata.name      # → minion-nyc-0, minion-nyc-1, ...
  - name: MINION_LOCATION
    value: {{ .Values.location | quote }}
```

The same `envsubst` initContainer (Decision 5) substitutes these into `org.opennms.minion.controller.cfg`. Stable pod names require StatefulSet (Decision 9).

### Decision 7: Core init phase — initContainer for v1

Core's install/upgrade phase (`opennms -i`) runs as an `initContainer` on every pod start. The OpenNMS installer is idempotent (skips work when `etc/configured` exists), so re-running on every restart is wasteful but correct.

**Alternatives considered:**

- *Helm pre-install/pre-upgrade Job.* Cleaner separation, better observability, time-bounded via `activeDeadlineSeconds`. Rejected for v1 because Helm hooks complicate ArgoCD/Flux sync waves and the current shape is already wired and working. Migration to a Job is captured as a v2 follow-up.

### Decision 8: Core persistence — single PVC at `/opennms-data`

Core writes RRD time-series files, uploaded MIBs, and generated reports under `/opennms-data`. The chart provides a single PVC mounted at that path:

```yaml
persistence:
  enabled: true
  storageClassName: ""        # cluster default
  size: 50Gi
  accessMode: ReadWriteOnce
```

Karaf data (`/opt/opennms/data`) and logs (`/opt/opennms/logs`) remain ephemeral (`emptyDir`); they are regenerable at startup.

### Decision 9: Minion workload kind — StatefulSet, no HPA

Minion is deployed as a **StatefulSet** with `replicas: 1` default and no HorizontalPodAutoscaler. Per-replica state lives on a per-pod PVC via `volumeClaimTemplates`.

**Why not Deployment+HPA (the current scaffold):**

- Each Minion registers under a unique ID. HPA scaling spawns new pods with new names → new IDs → registration churn and orphaned Minion entries in Core.
- Minion load is determined by *what* it's monitoring (configured externally), not by pod-level CPU/memory. HPA's signals don't track useful work.
- Minion has local Karaf bundle cache and per-replica state that benefits from PVCs.

For HA at one location, users set `replicaCount` to 2 or 3 — pods get stable IDs (`minion-nyc-0`, `minion-nyc-1`, `minion-nyc-2`) and each registers as a separate Minion in Core.

Sentinel keeps Deployment+HPA — it is stateless flow processing and autoscaling on CPU/load is the correct model there.

### Decision 10: Core healthchecks — staged

**v1** (this change):

```yaml
livenessProbe:
  tcpSocket:
    port: webui          # was: pgrep java
  initialDelaySeconds: 90
  periodSeconds: 30
  failureThreshold: 6

readinessProbe:
  httpGet:
    path: /opennms/login.jsp
    port: webui
  initialDelaySeconds: 90
  timeoutSeconds: 3
  failureThreshold: 20
  periodSeconds: 5
```

**v2 (deferred):** `/opennms/rest/health` httpGet probe with a credential strategy that does not weaken OpenNMS's default authentication.

### Decision 11: Edge-Sentinel pattern — not blessed

Sentinel ships only as a subchart of `opennms-stack`. It remains installable standalone (the chart is independently valid) but the chart provides no edge-specific knobs and no documented edge topology. Real flow-load scaling happens by raising Sentinel's `replicaCount` at the central site, not by edge deployment.

### Decision 12: Umbrella version pinning — strict pin

`opennms-stack/Chart.yaml` pins exact versions of its `core` and `sentinel` subchart dependencies:

```yaml
dependencies:
  - name: core
    version: =0.3.2          # exact
    repository: file://../core
  - name: sentinel
    version: =0.3.2
    repository: file://../sentinel
```

**Why not ranges (`~0.3` or `^0.3`):** OpenNMS Core and Sentinel must run the same OpenNMS major version (shared JPA schema, shared Karaf feature set). A range that quietly pulls a mismatched Sentinel during `helm dep update` is a real footgun. Strict pin makes the matched-pair invariant explicit at the umbrella level.

### Decision 13: Image tag default — fall through to `appVersion`

Each chart's `values.yaml`:

```yaml
image:
  repository: docker.io/opennms/<component>
  pullPolicy: IfNotPresent
  tag: ""                  # empty by default
```

Each chart's templates:

```yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

Each chart's `Chart.yaml`:

```yaml
appVersion: "35.0.5"       # lock-step across core/sentinel/minion
```

Releasing a new chart version implies a tested image pairing. Users can override with `--set image.tag=bleeding` for development. Renovate or Dependabot updates `appVersion` when a new Horizon version ships.

### Decision 14: Time-series strategy — RRD by default, BYO Prometheus-compatible backend via remote-writer plugin

The chart defaults `OPENNMS_TIMESERIES_STRATEGY=rrd` (OpenNMS's historical default) and writes RRD files to the `/opennms-data/rrd` PVC.

For users who want their time-series data in a Prometheus-compatible store (Cortex, Mimir, VictoriaMetrics, Thanos, plain Prometheus with remote-write-receiver), the chart integrates the [`opennms-forge/prometheus-remote-writer`](https://github.com/opennms-forge/prometheus-remote-writer) plugin via a `prometheusRemoteWriter:` values block:

```yaml
prometheusRemoteWriter:
  enabled: false
  version: "0.3.2"                    # KAR version to download
  kar:
    url: ""                            # override-able mirror URL; default
                                       # constructed from version against
                                       # GitHub releases
  writeUrl: ""                         # https://mimir.example/api/v1/push
  readUrl: ""                          # https://mimir.example/prometheus
  auth:
    existingSecret: ""                 # PRW_USERNAME, PRW_PASSWORD when set
```

When `enabled: true`, the chart adds a new initContainer (`download-plugins`) that wgets the KAR into a fresh `opennms-overlay` `emptyDir` mounted at `/opt/opennms-overlay/deploy/`. The upstream entrypoint's `applyOverlayConfig` step rsyncs it into `/opt/opennms/deploy/` where Karaf auto-deploys it. Two additional files are rendered into the etc-overlay:

- `org.opennms.plugins.tss.prometheus-remote-writer.cfg` — `write.url`, `read.url`, optional auth (envsubst placeholders)
- `opennms.properties.d/timeseries.properties` — `org.opennms.timeseries.strategy = integration`

**Why download at pod start instead of building a custom OpenNMS image:**

- Lower friction for users — no Dockerfile to maintain.
- The plugin version is decoupled from the OpenNMS chart's `appVersion` and can be bumped independently in values.
- The KAR is small (≤30MB) and fetched from a single GitHub Releases URL.

**Cost accepted:** network dependency at pod start. Air-gapped users override `prometheusRemoteWriter.kar.url` to point at an internal mirror. SHA-512 verification using the published `.kar.sha512` sidecar is a v2 follow-up.

**Why not Newts:**

Newts requires deploying or BYO-ing Cassandra, which doesn't fit this chart's "BYO Postgres + Kafka + Elasticsearch" infrastructure contract. The prometheus-remote-writer integration covers the same need (offload time-series to scalable external storage) without adding Cassandra to the dependency surface. Newts is intentionally excluded from values, templates, and the Karaf feature surface.

## Risks / Trade-offs

- **[Risk] Upstream `.cfg` file shape changes.** OpenNMS could rename keys in `org.opennms.core.ipc.*.cfg` or change file paths, breaking our etc-overlay.
  → **Mitigation**: chart versioning is independent of Horizon's `appVersion`; on a breaking upstream change, ship a chart minor bump and call it out in `tasks.md`. Lint-test in CI catches gross structural failures.

- **[Risk] Confd not actually inert.** A future upstream change could add a confd template that runs *after* the etc-overlay rsync, or add validation that fails on an empty YAML.
  → **Mitigation**: integration test in CI that asserts the rendered `.cfg` files in `/opt/opennms/etc/` after container start match what the chart templated, not the confd defaults.

- **[Risk] envsubst init container increases cold-start time.** ~50ms per pod, ~5MB image pull on first scheduling.
  → **Mitigation**: acceptable; image is small enough to fit in standard registry caches.

- **[Risk] StatefulSet Minion + per-pod PVC reduces scheduling flexibility.** PVCs pin pods to nodes (with most CSI drivers).
  → **Mitigation**: Minion's per-replica-state requirement is real and not optional; users with strict scheduling needs can disable persistence (`persistence.enabled: false`) and accept the cold-start re-bootstrapping cost.

- **[Risk] Strict-pin umbrella deps require frequent umbrella version bumps.** Every `core` or `sentinel` chart release bumps `opennms-stack`.
  → **Mitigation**: by design — matched-pair correctness is more important than version-bump ergonomics. Automate the bump via CI (the lint-test workflow can update the umbrella Chart.yaml in the same PR that bumps a subchart).

- **[Risk] BYO Secret schema drift.** Users may not know which keys we expect in a given `existingSecret` (e.g., `username` vs `user`, `password` vs `pass`).
  → **Mitigation**: document the expected key names per Secret in the chart README and in NOTES.txt; emit a clear template-time error (`required`) when a referenced Secret is missing.

- **[Risk] `OPENNMS_TIMESERIES_STRATEGY` defaults to `rrd`** which writes to disk continuously and grows over time.
  → **Mitigation**: 50Gi default PVC is sized for moderate deployments; users with large environments enable `prometheusRemoteWriter` to offload time-series to an external Prometheus-compatible store.

- **[Risk] prometheus-remote-writer KAR download fetches from GitHub at every pod start.** Network outages or GitHub rate limiting could prevent pod startup.
  → **Mitigation**: `prometheusRemoteWriter.kar.url` is override-able to an internal mirror. The kar is cached in the `opennms-overlay` emptyDir for the pod's lifetime, so reschedules trigger re-download but mid-pod restarts do not. v2 will add `.sha512` verification using the published sidecar.

- **[Risk] prometheus-remote-writer plugin version drift from OpenNMS Horizon major versions.** A future Horizon release could break the integration API the plugin targets.
  → **Mitigation**: the upstream README explicitly declares "OpenNMS Horizon Core 35+" compatibility; the chart pins a tested plugin version in values (`prometheusRemoteWriter.version: "0.3.2"`) and bumps it in lock-step with chart releases.

## Migration Plan

This change is additive for `core` (extends existing partial chart) and rewrites for `minion` and `sentinel`. The repository has no published chart releases yet; there are no downstream consumers to migrate.

For developers contributing to the repo:

1. The CNPG-backed `make install-postgres` flow continues to work for chart-testing.
2. The lint-and-test GitHub workflow extends to install `opennms-stack` end-to-end against the kind cluster + CNPG Postgres + a temporary Kafka and Elasticsearch (Strimzi operator and ECK operator, or simple single-pod stand-ins for CI only).
3. helm-docs runs as before; new charts produce new README.md files automatically.

## Open Questions

(none — the v1 design surface is closed; v2 follow-ups are explicitly listed as non-goals)
