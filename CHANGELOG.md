# Changelog

All notable changes to the four charts in this repository are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). All four charts (`core`, `sentinel`, `minion`, `opennms-stack`) are released together with a single chart `version` and the same `appVersion` (the OpenNMS Horizon release they were tested against).

## [Unreleased]

(no unreleased changes yet)

## [0.3.9] — 2026-07-08

### Added

- **`core`** — new `webAdmin` values block (default **enabled**) that bootstraps the Web UI `admin` password on first install. The chart generates a strong random password, stores it in a Kubernetes Secret (`<release>-opennms-admin`, keys `username`/`password`), and applies it to Horizon via a `post-install` hook `Job` running the `ghcr.io/no42-org/onmsctl` image: the Job waits for Core's REST API, authenticates as the upstream default `admin`/`admin`, and calls Horizon's `UserRestService` with `hashPassword=true` so the server hashes the value (no hash is computed chart-side and no `users.xml` is written). Administrators read the live password from the Secret:
  `kubectl get secret <release>-opennms-admin -o jsonpath='{.data.password}' | base64 -d`.
  **Bootstrap-seed semantics:** the password is set once at install and never re-asserted — the Secret is created only if absent (preserved across upgrades via Helm `lookup`), and operators can change the password in the UI afterward and it persists. Set `webAdmin.existingSecret` to apply a BYO password instead of generating one (with `webAdmin.existingSecretPasswordKey` when the Secret keys the password as something other than `password`; only the password is read — the account set is `webAdmin.username`), or `webAdmin.enabled: false` to disable the feature entirely. This closes the long-standing gap where Core shipped reachable with the public default `admin`/`admin`.
- **repo** — new `docker` Dependabot ecosystem entry scanning `charts/core`, tracking the `webAdmin.image` (onmsctl) pin and, as a side effect, the existing `alpine` config-renderer pin. See the caveat comment in `.github/dependabot.yml` about non-`docker.io` registries (dependabot-core #12207).

### Changed

- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all bump from `0.3.8` to `0.3.9`. Umbrella `dependencies` strict-pin updated to `=0.3.9`. `sentinel`, `minion`, and `opennms-stack` chart contents are unchanged (version bump only).

### Notes (upgrade impact for 0.3.8 → 0.3.9 users)

- **New default behavior on fresh installs.** A fresh `helm install` now rotates the `admin` password automatically and requires the `ghcr.io/no42-org/onmsctl` image to be reachable and Core to reach REST-ready within the hook's retry budget (`webAdmin.readiness.retries × intervalSeconds`, default ~10 min). Air-gapped operators mirror the image via `webAdmin.image.repository`; anyone who wants the old behavior sets `webAdmin.enabled: false`. `helm upgrade` does **not** re-run the hook and does **not** rotate an existing password. Because the hook is `post-install`, a failed hook marks the release failed even if Core is healthy; `helm install --wait`/`--atomic` must be given a `--timeout` ≥ `webAdmin.readiness.retries × intervalSeconds` (default ~10m).
- **⚠️ Umbrella coupling — Minion/Sentinel that authenticate to Core as `admin` will be locked out.** Under `opennms-stack`, any Minion or Sentinel wired to Core via `opennms.http.existingSecret` using the shared `admin` account loses access once the password rotates on install. Provision a dedicated low-privilege Core user for those components (a follow-up will wire this via `onmsctl apply -f`), or set `core.webAdmin.enabled: false` before installing. Kafka-IPC deployments that don't use HTTP SCV credentials are unaffected.
- **CI fixtures set `webAdmin.enabled: false`** so `ct install` never pulls the external image mid-test; the rendered shape is covered by helm-template tests.

## [0.3.8] — 2026-05-27

### Fixed

- **`core`** — Chart-rendered prometheus-remote-writer plugin cfg now lands at the correct filename for plugin v0.4.x. Plugin v0.4.x renamed its ConfigAdmin PID from `org.opennms.plugins.tss.prometheus-remote-writer` (hyphenated) to `org.opennms.plugins.tss.prometheusremotewriter` (collapsed); chart releases 0.3.0 through 0.3.7 kept writing the v0.3.x-shaped hyphenated filename, which Karaf's fileinstall left unbound to any service. Symptom under v0.4.x plugin: recurring `WARN | PrometheusRemoteWriterStorage | prometheus-remote-writer not yet configured (write.url is required ... waiting for ConfigAdmin to deliver real properties)` in `/opt/opennms/logs/karaf.log`; the plugin runs as a bundle but never picks up its cfg, so no samples are written to the remote backend. Discovered in `bbo-blinkenlights` at chart 0.3.7 + plugin v0.4.4. The chart now renders `org.opennms.plugins.tss.prometheusremotewriter.cfg`.

### Changed

- **`core`** — Chart-default `prometheusRemoteWriter.version` bumped from `0.3.2` to `0.4.4`. The KAR-download URL helper constructs the GitHub Releases URL from this value, so the chart's default install + the cfg filename now target the same plugin major. Both fixes go together — they were two halves of the same underlying drift between chart defaults and plugin lifecycle.
- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all bump from `0.3.7` to `0.3.8`. Umbrella `dependencies` strict-pin updated to `=0.3.8`. `sentinel`, `minion`, and `opennms-stack` chart contents are unchanged.

### Notes (upgrade impact for 0.3.7 → 0.3.8 users)

- **Operators with `prometheusRemoteWriter.enabled: true`** will see the plugin actually pick up its cfg on the next Core pod restart. If you applied a manual workaround at 0.3.7 (writing the cfg again at the collapsed filename via `core.extraConfigFiles."org.opennms.plugins.tss.prometheusremotewriter.cfg"`), remove that workaround on the upgrade — the chart now writes the correct filename directly and the workaround would only duplicate the cfg on disk.
- **Operators pinning `prometheusRemoteWriter.version` to a v0.3.x plugin** via values will hit the inverse problem (chart writes the collapsed filename, v0.3.x plugin expects hyphenated). Re-write the cfg through `core.extraConfigFiles."org.opennms.plugins.tss.prometheus-remote-writer.cfg"` until the pinned plugin version is updated. The chart targets the latest plugin major; the inverse hit on older plugins is documented but accepted.
- **No values surface change.** Existing operator values continue to work — only the rendered filename + chart-default version moves.
- **`bbo-blinkenlights` consumer cascade** — bbo bumps its helmfile pin from 0.3.7 to 0.3.8 AND removes the `extraConfigFiles."org.opennms.plugins.tss.prometheusremotewriter.cfg"` workaround it applied during the migrate-bbo-tsdb-to-prometheus-remote-write apply. End state: one plugin cfg file on disk.

### Known limitations (unchanged)

- **Functional Kafka TLS is still not wired** in any of the three charts. `kafka.tls.enabled=true` flips the protocol to `SSL` / `SASL_SSL`, but the chart does NOT mount the `tls.existingSecret` into the pod or emit `ssl.truststore.location` / `ssl.keystore.location` properties. Tracked for a follow-up lock-step release.
- **No typed `prometheusRemoteWriter.instanceId` values knob.** The plugin's `instance.id` cfg key disambiguates multi-OpenNMS deployments writing to a shared Prometheus-compatible backend. The chart-rendered cfg omits it; the plugin logs an informational WARN at startup. Harmless for single-instance backends. Tracked as a future enhancement.

## [0.3.7] — 2026-05-27

### Fixed

- **`sentinel`** — Sentinel's Kafka IPC consumer-side bundle (`org.opennms.core.ipc.sink.kafka.server`, hosts `KafkaMessageConsumerManager`) now starts cleanly at boot. 0.3.6 flipped Karaf's IPC feature selection from JMS to Kafka but exposed a deeper gap: the sink-server bundle's blueprint wires `OsgiKafkaConfigProvider` against PID `org.opennms.core.ipc.sink.kafka.consumer` — a separate cfg from the PID `org.opennms.core.ipc.sink.kafka` used by the sink-client bundle. The chart only wrote the latter. On 0.3.6, the sink-client started fine (producer connected to Kafka, Cluster ID retrieved), but the sink-server blueprint container failed with `Unable to initialize bean kafkaMessageConsumerManager` at `OsgiKafkaConfigProvider.getProperties` line 77 (`IOException` wrapped as `RuntimeException("Cannot load properties")`). Result: Sentinel could publish to Kafka but couldn't consume — `/opennms/rest/minions` returned `totalCount=0`. The chart now renders `org.opennms.core.ipc.sink.kafka.consumer.cfg` alongside the existing `org.opennms.core.ipc.sink.kafka.cfg` under the same `sentinel.kafkaBootstrap` gate, with identical content (the consumer bundle's blueprint supplies `group.id=OpenNMS` as a default).

### Changed

- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all bump from `0.3.6` to `0.3.7`. Umbrella `dependencies` strict-pin updated to `=0.3.7`. `core`, `minion`, and `opennms-stack` chart contents are unchanged.

### Notes (upgrade impact for 0.3.6 → 0.3.7 users)

- **Sentinel will register with Core for the first time** after this upgrade + a manual `kubectl rollout restart deploy/<release>-sentinel`. Sentinel pods that have been silently degraded since chart 0.3.0 — first because of the JMS-IPC default (fixed in 0.3.6), then because of the missing consumer cfg (fixed here) — will finally consume Kafka IPC traffic and complete the registration handshake. `/opennms/rest/minions` flips from `totalCount=0` to `totalCount=1`.
- **Manual Sentinel rollout still required after `helmfile apply`.** The Sentinel Deployment template doesn't carry a `checksum/config` annotation, so a ConfigMap content change doesn't auto-roll the pod. Tracked as a future improvement.
- **Operators using `extraConfigFiles."org.opennms.core.ipc.sink.kafka.consumer.cfg"`** — operator content continues to win; the chart-managed entry is only emitted when the operator hasn't overridden the path.
- **No values surface change.** Existing values files work unchanged at 0.3.7.

### Known limitations (unchanged)

- **Functional Kafka TLS is still not wired** in any of the three charts. `kafka.tls.enabled=true` flips the protocol to `SSL` / `SASL_SSL`, but the chart does NOT mount the `tls.existingSecret` into the pod or emit `ssl.truststore.location` / `ssl.keystore.location` properties. Tracked for a follow-up lock-step release.

## [0.3.6] — 2026-05-27

### Fixed

- **`sentinel`** — Sentinel now actually uses Kafka-IPC at boot. Prior chart releases (0.3.0 through 0.3.5) rendered the Kafka client config (`org.opennms.core.ipc.sink.kafka.cfg`) into the etc-overlay but never overrode Sentinel's stock `featuresBoot.d/ipc-strategy.boot` — the upstream image ships that file with `sentinel-jms` enabled and `!sentinel-kafka` (negated). Result: every chart-deployed Sentinel since 0.3.0 has booted with JMS-IPC, attempted to connect to a non-existent local ActiveMQ broker (`tcp://127.0.0.1:61616`, ~30-second retry loop), and never registered with Core via Kafka. The chart now writes `featuresBoot.d/ipc-strategy.boot` containing `!sentinel-jms\nsentinel-kafka\n` AND a symmetric `opennms.properties.d/disable-activemq.properties` (`org.opennms.activemq.broker.disable=true`) when a Kafka bootstrap is configured. Surfaced by `bbo-blinkenlights` install verification at chart 0.3.5: Sentinel pod `Ready=True` with `/opennms/rest/minions` returning `totalCount=0` and 1500+ ActiveMQ retries in `karaf.log`.

### Changed

- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all bump from `0.3.5` to `0.3.6`. Umbrella `dependencies` strict-pin updated to `=0.3.6`. `core`, `minion`, and `opennms-stack` chart contents are unchanged.

### Notes (upgrade impact for 0.3.5 → 0.3.6 users)

- **Sentinel will start producing real IPC traffic to Core for the first time** after this upgrade. Sentinel pods that have been silently degraded since chart 0.3.0 will roll, then boot with Kafka-IPC enabled, then register with Core. If you have downstream tooling that has been conditional on Sentinel being absent (e.g. monitoring dashboards that hide Sentinel rows because the registration was always empty), expect those views to start populating.
- **If you've been routing around the broken chart-deployed Sentinel via an external mechanism** (manually-configured Sentinel outside the chart, or an alternative IPC path), this is the upgrade that brings the chart-deployed Sentinel back online. Decide which Sentinel to keep before applying.
- **Operators using `extraConfigFiles` to write the same paths** (`featuresBoot.d/ipc-strategy.boot` or `opennms.properties.d/disable-activemq.properties`) — operator content continues to win; the chart-managed entries are only emitted when the operator hasn't already overridden the path.
- **No values surface change.** Existing values files work unchanged at 0.3.6.

### Known limitations (unchanged)

- **Functional Kafka TLS is still not wired** in any of the three charts. `kafka.tls.enabled=true` flips the protocol to `SSL` / `SASL_SSL`, but the chart does NOT mount the `tls.existingSecret` into the pod or emit `ssl.truststore.location` / `ssl.keystore.location` properties. Tracked for a follow-up lock-step release.

## [0.3.5] — 2026-05-27

### Added

- **`core` and `minion`** — new `icmp.enabled` values surface (boolean, default `true`). When enabled, the chart renders `spec.template.spec.securityContext.sysctls: [{name: net.ipv4.ping_group_range, value: "0 2147483647"}]` on the respective StatefulSet, granting every GID inside the pod the capability to open unprivileged `SOCK_DGRAM` ICMP sockets. This unblocks OpenNMS Pollerd and Discovery ICMP polling, which was silently broken in 0.3.0 through 0.3.4 — Core and Minion installed cleanly but could not even `ping localhost`. Operator-supplied `podSecurityContext` values pass through alongside; on a `sysctls` `name` collision, the chart-managed entry wins.
- **`core` and `minion`** — new post-install `helm test` hook Pod (`<release>-{core,minion}-test-icmp`) that mirrors the rendered sysctl and runs an `iputils`-based `ping -c 1 127.0.0.1` to verify unprivileged ICMP works in this cluster. When `icmp.enabled: false`, the test renders without the sysctl and prints a skip message (exit 0). Sentinel does not poll ICMP and has no test.

### Changed

- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all bump from `0.3.4` to `0.3.5`. Umbrella `dependencies` strict-pin updated to `=0.3.5`. `sentinel` chart contents are unchanged; the bump preserves the lock-step convention.

### Notes (upgrade impact for 0.3.4 → 0.3.5 users)

- **ICMP capability is on by default.** Existing Core and Minion deployments gain `net.ipv4.ping_group_range="0 2147483647"` on the pod's `securityContext.sysctls` at upgrade time. Pollerd/Discovery ICMP probes that previously failed silently will start succeeding — depending on your provisioning, this can show as new "node up" events for hosts that already had ICMP discovery configured but were never reachable. Review Pollerd / Discovery state after the upgrade if you have ICMP-conditional logic.
- **Hardened clusters that forbid `net.ipv4.ping_group_range`** must set `core.icmp.enabled: false` and/or `minion.icmp.enabled: false` before upgrading. Pod Security Standard `restricted` permits the sysctl by default since k8s 1.18 — most clusters need no action. Clusters with bespoke admission policy that block "safe" sysctls are the affected category.
- **`bbo-blinkenlights` consumers** — `add-bbo-netmon-deployment` task §4a (ICMP-capability blocker) clears with this release. Bump the helmfile pin from `0.3.4` to `0.3.5` and proceed with the install.

### Known limitations (unchanged)

- **Functional Kafka TLS is still not wired** in any of the three charts. `kafka.tls.enabled=true` flips the protocol to `SSL` / `SASL_SSL`, but the chart does NOT mount the `tls.existingSecret` into the pod or emit `ssl.truststore.location` / `ssl.keystore.location` properties. Tracked for a follow-up lock-step release.

## [0.3.4] — 2026-05-26

### Fixed

- **`sentinel`** — `-c` startup mode no longer crash-loops with `Error: Argument "password" is required` when only HTTP SCV credentials are wired. The upstream `/entrypoint.sh` `useEnvCredentials()` function invokes `scvcli set opennms.broker $OPENNMS_BROKER_USER $OPENNMS_BROKER_PASS` **unconditionally** alongside the HTTP call. Prior chart versions emitted only the HTTP env vars, so the broker `scvcli` call ran with both positional args empty and aborted the install init container. The chart now always emits both `OPENNMS_BROKER_USER` and `OPENNMS_BROKER_PASS` in `-c` mode — sourced from `opennms.broker.existingSecret` when set, otherwise as literal `value: "unused"` so the upstream call completes. Verified against `docker.io/opennms/sentinel:36.0.0` (chart-pinned) and `quay.io/bluebird/sentinel:37.0.0`.

### Added

- **`sentinel`** — new `opennms.broker.existingSecret` values surface, mirroring the existing `opennms.http.existingSecret` shape. Set this when your deployment uses a JMS broker and you want real broker credentials in `etc/scv.jce`. The Secret must carry keys `OPENNMS_BROKER_USER` and `OPENNMS_BROKER_PASS`. Kafka-IPC deployments leave this empty and rely on the chart's fallback to satisfy the upstream entrypoint.

### Changed

- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all bump from `0.3.3` to `0.3.4`. Umbrella `dependencies` strict-pin updated to `=0.3.4`. `core` and `minion` chart contents are unchanged; the bump preserves the lock-step convention.

### Notes (upgrade impact for 0.3.3 → 0.3.4 users)

- **Dummy `opennms.broker` credentials in `etc/scv.jce` on Kafka-IPC deployments.** After upgrade, Sentinel pods that don't set `opennms.broker.existingSecret` will have an `opennms.broker` alias in `etc/scv.jce` with username/password both literally `unused`. The alias is never consulted in Kafka-IPC mode (broker IPC is disabled at the Core side via `disable-activemq.properties`). Operators running on JMS IPC SHOULD provision a real broker Secret and set `sentinel.opennms.broker.existingSecret` before upgrading; the dummy values would otherwise fail JMS broker authentication at runtime.
- **No values changes required for Kafka-IPC deployments** (the common case, including `bbo-blinkenlights`). The fallback path is automatic.

### Known limitations (unchanged)

- **Functional Kafka TLS is still not wired** in any of the three charts. `kafka.tls.enabled=true` flips the protocol to `SSL` / `SASL_SSL`, but the chart does NOT mount the `tls.existingSecret` into the pod or emit `ssl.truststore.location` / `ssl.keystore.location` properties. Tracked for a follow-up lock-step release.

## [0.3.3] — 2026-05-24

### Fixed

- **`core`** — Stale `featuresBoot.d/kafka-{ipc,rpc,sink,twin}.boot` files written by chart ≤0.3.1 now get removed from the persistent etc directory at every pod start. The 0.3.2 fix stopped *writing* these files, but the upstream entrypoint's `applyOverlayConfig` is additive — files dropped from the chart's overlay survive on the PVC across upgrades. Result on 0.3.1→0.3.2 upgrade: Karaf failed with `Error resolving artifact org.opennms.core.ipc.rpc:org.opennms.core.ipc.rpc.kafka:jar:36.0.0` and Core never started. 0.3.3 extends the envsubst init container to mount the PVC and `rm -f` the four well-known stale paths before the install container runs.

### Added

- **`core`** — new `core.daemons.<short-name>.enabled` values surface for per-daemon enable/disable. Upstream `etc/service-configuration.xml` already wraps every Core daemon's `enabled` attribute in `${env:CORE_SERVICE_<NAME>_ENABLED|<default>}`, so the chart projects a `CORE_SERVICE_<STEM>_ENABLED=false` env var into both Core containers when an operator flips `enabled: false` — no XML editing, no extra init container, no init image expansion. First (and only) wired daemon: `ackd`. Unknown short-names fail `helm template` with a clear error listing the whitelist. Adding the next daemon is one entry in `core.daemonsEnvWhitelist` (`charts/core/templates/_helpers.tpl`) plus one entry in `values.yaml`.

### Changed

- **`core`** — `daemons.ackd.enabled` defaults to `false`. Ackd is on the upstream deprecation track and most deployments don't use it. Operators who still rely on alarm acknowledgement workflows that depend on Ackd MUST set `core.daemons.ackd.enabled: true` explicitly on upgrade.
- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all bump from `0.3.2` to `0.3.3`. Umbrella `dependencies` strict-pin updated to `=0.3.3`. `sentinel` and `minion` chart contents are unchanged; the bump preserves the lock-step convention.

### Breaking changes (upgrade impact for 0.3.2 → 0.3.3 users)

- **`core` — Ackd is disabled by default.** Existing 0.3.2 deployments that depended on the upstream `enabled="true"` default for Ackd will see the daemon silently switched off after the upgrade. Mitigation: set `core.daemons.ackd.enabled: true` in your values before upgrading. The chart prints no warning when Ackd is disabled (the values block is the source of truth).
- **`core` — operator-supplied `extraConfigFiles."featuresBoot.d/kafka-{ipc,rpc,sink,twin}.boot"` files will be deleted from the PVC at every pod start.** The cleanup `rm -f` runs unconditionally and targets exact filenames; the operator's overlay re-renders the files on each install, but the cleanup runs before the overlay copy. Mitigation: if you depend on bespoke `kafka-*.boot` content (unlikely — the bundles don't ship in any Horizon 35/36 image), rename to a non-conflicting filename.

### Known limitations (unchanged)

- **Functional Kafka TLS is still not wired** in any of the three charts. `kafka.tls.enabled=true` flips the protocol to `SSL` / `SASL_SSL`, but the chart does NOT mount the `tls.existingSecret` into the pod or emit `ssl.truststore.location` / `ssl.keystore.location` properties. Tracked for a follow-up lock-step release.

## [0.3.2] — 2026-05-23

### Fixed

- **`core`** — Kafka IPC config is now written as system properties in `opennms.properties.d/kafka-ipc.properties` with the `org.opennms.core.ipc.kafka.` prefix, instead of `.cfg` files plus `featuresBoot.d/kafka-*.boot` directives. Core reads Kafka IPC config via `OnmsKafkaConfigProvider` (system-property scan, prefix-stripped), not Karaf ConfigAdmin — the `.cfg` writes were dead, and the `featuresBoot.d` writes referenced `opennms-core-ipc-{rpc,sink,twin}-kafka` features whose implementation bundles (`org.opennms.core.ipc.rpc.kafka`, `org.opennms.core.ipc.sink.kafka.client`, `org.opennms.core.ipc.twin.kafka.subscriber`) are not shipped in the `opennms/horizon:36.0.0` (and `35.x`) OCI image. The Karaf resolver consequently fails at boot with `Error downloading mvn:...` and Core never starts when `kafka.bootstrapServers` is set. The new path matches what `OpenNMSContainer.java` in the upstream smoke harness does — and is the only path that actually works on the published Horizon image.

### Changed

- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all bump from `0.3.1` to `0.3.2`. Umbrella `dependencies` strict-pin updated to `=0.3.2`. `sentinel` and `minion` chart contents are unchanged; the bump preserves the lock-step convention.

### Breaking changes (upgrade impact for 0.3.1 → 0.3.2 users)

- **`core` — three `.cfg` paths and four `featuresBoot.d` paths in the Core etc-overlay are gone.** Operators who set `extraConfigFiles."org.opennms.core.ipc.{sink,rpc,twin}.kafka.cfg": ...` or `extraConfigFiles."featuresBoot.d/kafka-{ipc,rpc,sink,twin}.boot": ...` to override the chart-managed entries will still see their content written to the etc-overlay, but it will no longer be matched by a chart-managed entry — those overrides become inert dead writes that Core does not read. Re-express any Kafka client tunings as `kafka.extraProperties` (rendered with the `org.opennms.core.ipc.kafka.` prefix into the new properties file) instead.

### Known limitations (unchanged)

- **Functional Kafka TLS is still not wired** in any of the three charts. `kafka.tls.enabled=true` flips the protocol to `SSL` / `SASL_SSL`, but the chart does NOT mount the `tls.existingSecret` into the pod or emit `ssl.truststore.location` / `ssl.keystore.location` properties. For TLS-encrypted Kafka right now, operators must mount the Secret and emit the truststore properties via `extraConfigFiles` themselves. Full TLS wiring is targeted for a follow-up release across all three charts in lock-step.

## [0.3.1] — 2026-05-23

### Changed

- **All four charts** — `appVersion` bumped from `35.0.5` to `36.0.0` (latest stable OpenNMS Horizon release, published 2026-05-12). Chart values surface and templates are unchanged; the bump is image-only. Horizon 36.0.0 introduces DB-backed configuration for SNMP, data collection, Trapd, and eventconf — these schema migrations are applied automatically by Liquibase at Core boot on first install or upgrade.
- **`minion`** — chart `version` bumped from `0.2.0` to `0.3.1` to re-establish the lock-step convention (`core`, `sentinel`, `minion`, `opennms-stack` all release together with the same chart `version`). The 0.2.0 → 0.3.1 jump skips a `0.3.0` Minion tag — Minion was not affected by 0.3.0's Postgres-surface change and was deliberately left behind; this release brings it back in line.
- **All four charts** — strict-pin cascade: `core`, `sentinel`, `minion`, `opennms-stack` all at `0.3.1`. Umbrella `dependencies` strict-pin updated to `=0.3.1` for both `core` and `sentinel`.

### Notes

- Existing 0.3.0 (Horizon 35.0.5) installs upgrading to 0.3.1 will trigger the 35.x → 36.x Liquibase migration on the next Core pod restart. Snapshot the database first.
- Fresh 0.3.1 installs against an empty database run the 36.0.0 schema bootstrap end-to-end — no migration involved.

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

[Unreleased]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.9...HEAD
[0.3.9]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.8...v0.3.9
[0.3.8]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.7...v0.3.8
[0.3.7]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/labmonkeys-space/opennms-helm-charts/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/labmonkeys-space/opennms-helm-charts/releases/tag/v0.1.0
