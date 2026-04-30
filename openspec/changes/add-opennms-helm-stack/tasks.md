## 1. Shared chart helpers

- [x] 1.1 Define a shared `_envsubst-init` helper template (or copy-pasted partial) that produces the initContainer + emptyDir volume + volumeMounts for the envsubst pattern; reusable by `core`, `sentinel`, and `minion`.
- [x] 1.2 Define a shared `_global-values` helper that, when used inside a subchart, returns `.Values.global.<key>` if set, else `.Values.<key>` (used by `core` and `sentinel` under the umbrella).
- [x] 1.3 Pick the envsubst init image (e.g., `alpine:3.19` + `apk add --no-cache gettext`, or a pre-built `bhgedigital/envsubst`-style image) and document the choice in the chart README.

## 2. Core chart — fill out the wiring

- [x] 2.1 Update `charts/core/Chart.yaml`: bump `version` (chart semver), set `appVersion: "35.0.5"`, ensure `apiVersion: v2` and `type: application`.
- [x] 2.2 Update `charts/core/values.yaml`: replace bleeding tag default with empty `tag: ""`; add `instanceId`, `kafka.*` (bootstrapServers, auth, tls, extraProperties), `elasticsearch.*` (optional), `persistence.*`, `extraConfigFiles`, `prometheus.jmxExporter.*`, `javaOpts` blocks; restructure `postgresql.*` to use `auth.existingSecret` + fall-through to inline username/password.
- [x] 2.3 Add `templates/core-config-templates.yaml` (ConfigMap) carrying `.cfg` placeholders for `org.opennms.core.ipc.{sink,rpc,twin}.kafka.cfg` and `instance-id.properties`; use `${KAFKA_*}` placeholders for any Kafka SASL/TLS values.
- [x] 2.4 Add `templates/core-config-overlay.yaml` — empty `horizon-config.yaml` ConfigMap mounted at `/opt/opennms/horizon-config.yaml`.
- [x] 2.5 Update `templates/statefulset.yaml`: add envsubst initContainer (per 1.1); add emptyDir volume mounted at `/opt/opennms-etc-overlay/etc/`; mount empty horizon-config ConfigMap at `/opt/opennms/horizon-config.yaml`; wire env vars from `postgresql.auth.existingSecret`; switch liveness from `pgrep java` to `tcpSocket` on the `webui` named port; add per-component PVC `volumeClaimTemplate` at `/opennms-data` gated by `persistence.enabled`.
- [x] 2.6 Drop `templates/core-credentials.yaml` if its only purpose is templating the chart-managed Secret; replace usage with `existingSecret` references throughout. Keep a small "lab-mode" Secret rendering path gated by absence of `existingSecret` (so default `make test-install-core` still works against CNPG).
- [x] 2.7 Update `templates/_helpers.tpl` with helpers for: image (`core.image`), Kafka SASL JAAS string assembly, env-block for Postgres credentials, envsubst initContainer block.
- [x] 2.8 Update `templates/NOTES.txt` to print the documented `existingSecret` keys (`username`, `password`) and how to override.
- [x] 2.9 Run `make readme` to regenerate `charts/core/README.md` and verify the values table covers the new keys.
- [x] 2.10 Add `prometheusRemoteWriter.*` block to `charts/core/values.yaml` (`enabled`, `version`, `kar.url`, `writeUrl`, `readUrl`, `auth.existingSecret`).
- [x] 2.11 Add a `download-plugins` initContainer in `charts/core/templates/statefulset.yaml` (gated on `prometheusRemoteWriter.enabled`) that wgets the KAR into a new `opennms-overlay` emptyDir mounted at `/opt/opennms-overlay/`. Mount the same emptyDir on `core-init` and the runtime container so the upstream `applyOverlayConfig` step rsyncs `deploy/` into `/opt/opennms/`.
- [x] 2.12 In `charts/core/templates/core-config-templates.yaml` add (gated): `org.opennms.plugins.tss.prometheus-remote-writer.cfg` with envsubst placeholders for auth, and `opennms.properties.d/timeseries.properties` setting `org.opennms.timeseries.strategy = integration`.
- [x] 2.13 In `_helpers.tpl` add helpers: `core.prometheusRemoteWriterKarUrl` (constructs default URL from version, override-able), `core.prometheusRemoteWriterEnv` (env vars for the envsubst init when auth is set).

## 3. Sentinel chart — replace nginx scaffold with real Sentinel

- [x] 3.1 Update `charts/sentinel/Chart.yaml`: set `appVersion: "35.0.5"`, bump chart `version`.
- [x] 3.2 Update `charts/sentinel/values.yaml`: replace `nginx` image with `docker.io/opennms/sentinel`, set `tag: ""`; add `instanceId`, `location`, `opennms.http.existingSecret`, `opennms.broker.existingSecret`, `postgresql.*`, `kafka.*`, `elasticsearch.*`, `extraConfigFiles`, `prometheus.jmxExporter.*`, `javaOpts`; remove the `httpRoute`, `ingress`, `hpa`, `service` shapes inherited from `helm create` that aren't appropriate (Sentinel typically has no HTTP ingress, only Karaf shell + JMX).
- [x] 3.3 Replace `templates/deployment.yaml`: keep Deployment kind (Sentinel is stateless); add envsubst initContainer; add envFrom `valueFrom.secretKeyRef` for the four `OPENNMS_HTTP_*` / `OPENNMS_BROKER_*` env vars; mount empty `sentinel-config.yaml` at `/opt/sentinel/sentinel-config.yaml`; mount emptyDir at `/opt/sentinel-etc-overlay/etc/`.
- [x] 3.4 Drop `templates/ingress.yaml` and `templates/httproute.yaml` (Sentinel has no public HTTP surface).
- [x] 3.5 Add `templates/sentinel-config-templates.yaml` (ConfigMap) carrying `.cfg` placeholders for `org.opennms.netmgt.distributed.datasource.cfg`, `org.opennms.core.ipc.sink.kafka.cfg`, `org.opennms.features.flows.persistence.elastic.cfg`, `instance-id.properties`.
- [x] 3.6 Keep `templates/hpa.yaml` (Sentinel scales horizontally) and gate on `autoscaling.enabled`.
- [x] 3.7 Update `templates/_helpers.tpl` with helpers analogous to Core's, plus the `_global-values` helper from 1.2 to read shared umbrella values.
- [x] 3.8 Update `templates/NOTES.txt` with the BYO Secret key conventions.
- [x] 3.9 Run `make readme` to regenerate `charts/sentinel/README.md`.
- [x] 3.10 Update `templates/tests/test-connection.yaml` to test something meaningful (e.g., Karaf shell port reachable).

## 4. Minion chart — replace nginx scaffold with real Minion

- [x] 4.1 Update `charts/minion/Chart.yaml`: set `appVersion: "35.0.5"`, bump chart `version`.
- [x] 4.2 Update `charts/minion/values.yaml`: replace `nginx` image with `docker.io/opennms/minion`, set `tag: ""`; add `instanceId`, `location` (required), `opennms.http.existingSecret`, `opennms.broker.existingSecret`, `kafka.*`, `dominion.*` (optional gRPC), `persistence.*`, `extraConfigFiles`, `prometheus.jmxExporter.*`, `javaOpts`; remove inherited `helm create` shapes that don't apply (HTTP ingress, HPA).
- [x] 4.3 Replace `templates/deployment.yaml` with `templates/statefulset.yaml`: StatefulSet kind, no HPA template; downward-API env vars `MINION_ID` (from `metadata.name`) and `MINION_LOCATION` (from values); envsubst initContainer; emptyDir at `/opt/minion-etc-overlay/etc/`.
- [x] 4.4 Delete `templates/hpa.yaml`, `templates/ingress.yaml`, `templates/httproute.yaml` (none apply to Minion).
- [x] 4.5 Add `templates/minion-config-templates.yaml` (ConfigMap) carrying `.cfg` placeholders for `org.opennms.minion.controller.cfg` (with `${MINION_ID}` / `${MINION_LOCATION}`), `org.opennms.core.ipc.{sink,rpc,twin}.kafka.cfg`, `instance-id.properties`, and the four `kafka-*.boot` files (static content).
- [x] 4.6 Add `templates/minion-config-overlay.yaml` — empty `minion-config.yaml` mounted at `/opt/minion/minion-config.yaml`.
- [x] 4.7 Add `volumeClaimTemplates` for `/opt/minion/data` gated on `persistence.enabled` (default 1Gi, ReadWriteOnce).
- [x] 4.8 Update `templates/_helpers.tpl` with Minion-specific helpers.
- [x] 4.9 Update `templates/NOTES.txt` to surface the per-pod `MINION_ID` pattern and document HA via `replicaCount`.
- [x] 4.10 Run `make readme` to regenerate `charts/minion/README.md`.

## 5. opennms-stack umbrella

- [x] 5.1 Create `charts/opennms-stack/Chart.yaml` — `apiVersion: v2`, `type: application`, `name: opennms-stack`, `version: 0.1.0` (initial), `appVersion: "35.0.5"`, `dependencies` block strict-pinning `core` and `sentinel` from `file://../core` and `file://../sentinel`.
- [x] 5.2 Create `charts/opennms-stack/values.yaml` — `global.*` block (instanceId, postgresql, kafka, elasticsearch), per-subchart override blocks `core: {}` and `sentinel: {}` documented with comments.
- [x] 5.3 Create `charts/opennms-stack/.helmignore`, `charts/opennms-stack/templates/NOTES.txt` (post-install hints), and a `charts/opennms-stack/templates/_helpers.tpl` if any umbrella-level helpers are needed.
- [x] 5.4 Wire the `_global-values` helper in Core and Sentinel subcharts so they read `global.*` first, fall back to local values.
- [x] 5.5 Run `helm dep update charts/opennms-stack` to populate `charts/opennms-stack/charts/` and verify lock-file generation.
- [x] 5.6 Run `helm template stack charts/opennms-stack` and verify Core + Sentinel resources render, no Minion appears, and no infrastructure workloads appear.
- [x] 5.7 Run `make readme` to generate `charts/opennms-stack/README.md`.

## 6. Makefile and CI integration

- [x] 6.1 Add `make test-install-stack` target that creates the kind cluster, installs CNPG, installs a single-pod Kafka (Strimzi quickstart manifest or kraft mode `apache/kafka` image as a Deployment + Service), installs a single-pod Elasticsearch (`bitnami/elasticsearch` image or ECK quickstart for CI), then runs `ct install --charts charts/opennms-stack`.
- [x] 6.2 Add `make clean-kafka` and `make clean-elasticsearch` targets that mirror the existing `clean-postgres` pattern.
- [x] 6.3 Update `make install-all` to include the new umbrella + minion install steps.
- [x] 6.4 Update `.github/workflows/lint-and-test.yaml` to invoke the new make targets; ensure all four charts (core, sentinel, minion, opennms-stack) are linted.
- [x] 6.5 Verify the `ct.yaml` / `lint-and-test` config picks up all four chart directories.

## 7. Documentation

- [x] 7.1 Update top-level `README.md` with a "Which chart should I install?" matrix (central site → `opennms-stack`; remote location → `minion` per location).
- [x] 7.2 Per-chart `README.md`: document the BYO Secret key conventions (e.g., `opennms-postgres` requires `username` and `password`), the etc-overlay escape hatch (`extraConfigFiles`), and where to find the `appVersion` ↔ Horizon version mapping.
- [x] 7.3 Add a top-level `CONTRIBUTING.md` (or expand an existing one) noting the `appVersion` lock-step convention and the strict-pin umbrella dependency policy.

## 8. Validation

- [x] 8.1 `make lint` passes for all four charts.
- [ ] 8.2 `make test-install-stack` succeeds end-to-end on a fresh kind cluster. *(needs kind run; verifiable in CI)*
- [ ] 8.3 `make test-install-minion` succeeds standalone (no Postgres/ES needed). *(needs kind run; verifiable in CI)*
- [x] 8.4 `helm template` output for each chart matches the requirement scenarios in `specs/`: tcpSocket liveness on Core, no Minion in umbrella, empty confd YAMLs, etc.
- [x] 8.5 Run `openspec validate add-opennms-helm-stack` and resolve any spec/format errors.
