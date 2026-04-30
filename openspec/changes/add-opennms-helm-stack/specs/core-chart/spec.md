## ADDED Requirements

### Requirement: Core image source and version pinning

The `core` chart SHALL deploy OpenNMS Horizon Core from the upstream image `docker.io/opennms/horizon`. The chart's `Chart.yaml` SHALL declare `appVersion: "35.0.5"`. The default `image.tag` value SHALL be the empty string, and the StatefulSet template SHALL fall through to `.Chart.AppVersion` when `image.tag` is unset.

#### Scenario: Default install pins the tested image tag

- **WHEN** a user runs `helm install onms charts/core` without overriding `image.tag`
- **THEN** the rendered StatefulSet uses image `docker.io/opennms/horizon:35.0.5`

#### Scenario: User overrides image tag for development

- **WHEN** a user runs `helm install onms charts/core --set image.tag=bleeding`
- **THEN** the rendered StatefulSet uses image `docker.io/opennms/horizon:bleeding`

### Requirement: Core deploys as a single-replica StatefulSet

The `core` chart SHALL deploy Core as a `StatefulSet` with `replicas: 1`. The chart SHALL NOT expose a HorizontalPodAutoscaler for Core. The StatefulSet's headless Service SHALL be named `<release>-core-headless`.

#### Scenario: Single replica by default

- **WHEN** the chart is installed with default values
- **THEN** the resulting StatefulSet has `spec.replicas: 1`

### Requirement: Core connects to BYO Postgres via env vars

The `core` chart SHALL configure Postgres connectivity through direct environment variables on the runtime container: `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `OPENNMS_DBNAME`, `OPENNMS_DBUSER`, `OPENNMS_DBPASS`. Non-secret env vars (`POSTGRES_HOST`, `POSTGRES_PORT`, `OPENNMS_DBNAME`) SHALL come from a chart-rendered `ConfigMap` referenced via `envFrom`. Credential env vars (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `OPENNMS_DBUSER`, `OPENNMS_DBPASS`) SHALL come from a referenced Kubernetes `Secret` (either user-supplied via `auth.existingSecret`, or chart-rendered in lab mode) referenced via `envFrom: secretRef`. The chart SHALL NOT deploy Postgres.

#### Scenario: User provides existing Secret with Postgres credentials

- **WHEN** the chart is installed with `postgresql.auth.existingSecret: opennms-postgres` and `postgresql.host: postgres.db.svc.cluster.local`
- **THEN** the StatefulSet's container has `POSTGRES_HOST=postgres.db.svc.cluster.local` set via `envFrom` against the chart's env ConfigMap
- **AND** the container has an `envFrom: secretRef: name: opennms-postgres` entry that exposes `POSTGRES_USER`, `POSTGRES_PASSWORD`, `OPENNMS_DBUSER`, `OPENNMS_DBPASS` as env vars

#### Scenario: Chart never deploys Postgres

- **WHEN** the chart is rendered with any combination of values
- **THEN** no `Deployment`, `StatefulSet`, or other workload resource for Postgres appears in the output

### Requirement: Core configures Kafka via etc-overlay

The `core` chart SHALL render Kafka IPC configuration into `.cfg` files mounted to `/opt/opennms-etc-overlay/etc/`. The chart SHALL render at minimum `org.opennms.core.ipc.sink.kafka.cfg`, `org.opennms.core.ipc.rpc.kafka.cfg`, and `org.opennms.core.ipc.twin.kafka.cfg`, each carrying the same `bootstrap.servers` value. The chart SHALL also render `instance-id.properties` containing the value of `instanceId` (default `OpenNMS`). The chart SHALL NOT support ActiveMQ or any non-Kafka broker.

#### Scenario: Kafka bootstrap servers reach all three IPC config files

- **WHEN** the chart is installed with `kafka.bootstrapServers: "k1:9092,k2:9092"`
- **THEN** the rendered ConfigMap contains `org.opennms.core.ipc.sink.kafka.cfg.tmpl`, `org.opennms.core.ipc.rpc.kafka.cfg.tmpl`, and `org.opennms.core.ipc.twin.kafka.cfg.tmpl`
- **AND** each file contains `bootstrap.servers=k1:9092,k2:9092`

#### Scenario: Instance ID prefix defaults to OpenNMS

- **WHEN** the chart is installed without overriding `instanceId`
- **THEN** the rendered `instance-id.properties` contains `org.opennms.instance.id=OpenNMS`

### Requirement: Mixed-content .cfg files use envsubst initContainer

When a rendered `.cfg` file contains both non-secret values and references to credentials from a Secret, the chart SHALL use the following pattern:

1. A `ConfigMap` carries the `.cfg` template containing `${VAR_NAME}` placeholders.
2. A `Secret` reference (or chart-managed Secret) supplies the credentials as environment variables.
3. An `initContainer` runs `envsubst` over the templates and writes the resolved files to an `emptyDir` volume.
4. The runtime container mounts the `emptyDir` at `/opt/opennms-etc-overlay/etc/`.

The chart SHALL NOT use Helm's `lookup` function to read existing Secrets at template time.

#### Scenario: Envsubst init container produces resolved Kafka SASL config

- **WHEN** the chart is installed with `kafka.auth.enabled: true` and `kafka.auth.existingSecret: opennms-kafka`
- **THEN** the StatefulSet pod spec contains an initContainer named `envsubst-config` (or similar) that mounts the placeholder ConfigMap and the Secret as env vars
- **AND** the runtime container mounts the resulting `emptyDir` volume at `/opt/opennms-etc-overlay/etc/`

### Requirement: Confd is left inert

The `core` chart SHALL mount an empty (`{}`) `horizon-config.yaml` at `/opt/opennms/horizon-config.yaml` so that confd's `file` backend has a valid input file. The chart SHALL NOT populate that file with any non-empty configuration.

#### Scenario: Confd YAML overlay is empty

- **WHEN** the chart renders templates
- **THEN** there is exactly one ConfigMap whose key resolves to the file `horizon-config.yaml`
- **AND** the contents of that key parse as the empty YAML object `{}`

### Requirement: Core persistence is a single PVC at /opennms-data

The `core` chart SHALL provide a single PersistentVolumeClaim mounted at `/opennms-data` when `persistence.enabled` is `true`. The default size SHALL be `50Gi`, the default `accessMode` SHALL be `ReadWriteOnce`, and the default `storageClassName` SHALL be unset (inheriting the cluster default). Karaf data (`/opt/opennms/data`) and logs (`/opt/opennms/logs`) SHALL use `emptyDir` volumes.

#### Scenario: Default persistence creates a PVC

- **WHEN** the chart is installed with default values
- **THEN** the StatefulSet has a `volumeClaimTemplate` mounted at `/opennms-data` with `requests.storage: 50Gi`

#### Scenario: Persistence can be disabled

- **WHEN** the chart is installed with `persistence.enabled: false`
- **THEN** no `PersistentVolumeClaim` or `volumeClaimTemplate` is rendered for Core
- **AND** `/opennms-data` is mounted as `emptyDir`

### Requirement: Core install/upgrade runs as an initContainer

The `core` chart SHALL run the OpenNMS install/upgrade phase (`opennms -i`) as an `initContainer` on the StatefulSet pod. The chart SHALL NOT use Helm hooks or a separate `Job` resource for the install phase in v1.

#### Scenario: InitContainer present on the StatefulSet

- **WHEN** the chart renders templates
- **THEN** the StatefulSet's pod spec contains an initContainer that invokes the same image with the `-i` flag

### Requirement: Core healthchecks (v1)

The `core` chart's StatefulSet SHALL define a `livenessProbe` of type `tcpSocket` against the `webui` container port. The `readinessProbe` SHALL be an `httpGet` against `/opennms/login.jsp` on the `webui` port. The chart SHALL NOT use the `pgrep java` command-style probe.

#### Scenario: Liveness uses tcpSocket

- **WHEN** the chart renders templates
- **THEN** the container's `livenessProbe.tcpSocket.port` equals the `webui` named port
- **AND** the container's `livenessProbe` does not contain an `exec` command

#### Scenario: Readiness uses login.jsp

- **WHEN** the chart renders templates
- **THEN** the container's `readinessProbe.httpGet.path` equals `/opennms/login.jsp`
- **AND** the container's `readinessProbe.httpGet.port` equals the `webui` named port

### Requirement: Time-series strategy — RRD by default, optional Prometheus remote-writer

The `core` chart SHALL default `OPENNMS_TIMESERIES_STRATEGY` to `rrd` and write RRD files to the persistent `/opennms-data/rrd` directory. The chart SHALL accept a `prometheusRemoteWriter.*` values block; when `prometheusRemoteWriter.enabled` is `true` the chart SHALL:

1. Add an initContainer that downloads the KAR for the configured `prometheusRemoteWriter.version` into the OpenNMS overlay directory (`/opt/opennms-overlay/deploy/`).
2. Render `org.opennms.plugins.tss.prometheus-remote-writer.cfg` into the etc-overlay with `write.url`, `read.url`, and (when `auth.existingSecret` is set) basic-auth credentials substituted via the envsubst initContainer.
3. Render `opennms.properties.d/timeseries.properties` into the etc-overlay containing `org.opennms.timeseries.strategy = integration`.

The `core` chart SHALL NOT model Newts or Cassandra in any values, templates, or env vars.

#### Scenario: Default install uses RRD strategy

- **WHEN** the chart is installed with default values (`prometheusRemoteWriter.enabled: false`)
- **THEN** the rendered chart contains no `download-plugins` initContainer
- **AND** the `OPENNMS_TIMESERIES_STRATEGY` env var is set to `rrd`
- **AND** no `timeseries.properties` file is rendered into the etc-overlay

#### Scenario: Remote-writer enabled wires KAR download and config

- **WHEN** the chart is installed with `prometheusRemoteWriter.enabled: true`, `prometheusRemoteWriter.version: "0.3.2"`, `prometheusRemoteWriter.writeUrl: "https://mimir.example/api/v1/push"`
- **THEN** the StatefulSet pod spec contains an initContainer named `download-plugins` that wgets the KAR for v0.3.2 into a volume that lands at `/opt/opennms-overlay/deploy/`
- **AND** the etc-overlay ConfigMap contains `org.opennms.plugins.tss.prometheus-remote-writer.cfg` with `write.url=https://mimir.example/api/v1/push`
- **AND** the etc-overlay contains `opennms.properties.d/timeseries.properties` with `org.opennms.timeseries.strategy = integration`

#### Scenario: Newts is not exposed

- **WHEN** the chart is rendered with any values
- **THEN** no `OPENNMS_TIMESERIES_STRATEGY=newts` env var is settable through documented values keys
- **AND** no Cassandra/Newts-related ConfigMap or template is rendered

### Requirement: ServiceAccount creation

The `core` chart SHALL render a `ServiceAccount` resource when `serviceAccount.create` is `true` (the default). The ServiceAccount's name SHALL match the value the StatefulSet's `serviceAccountName` field resolves to, so the pod can be scheduled without a "service account not found" admission failure. The ServiceAccount SHALL carry the same labels as other chart-managed resources.

#### Scenario: Default install creates a ServiceAccount

- **WHEN** the chart is installed with default values
- **THEN** the rendered output contains a `ServiceAccount` resource
- **AND** the StatefulSet's `spec.template.spec.serviceAccountName` matches the rendered ServiceAccount's `metadata.name`

#### Scenario: ServiceAccount creation can be disabled

- **WHEN** the chart is installed with `serviceAccount.create: false` and `serviceAccount.name: my-existing-sa`
- **THEN** no `ServiceAccount` resource is rendered by the chart
- **AND** the StatefulSet's `spec.template.spec.serviceAccountName` equals `my-existing-sa`

### Requirement: Escape hatch for additional config files

The `core` chart SHALL accept a `extraConfigFiles` map in its values where keys are filenames (e.g., `org.opennms.foo.cfg`) and values are file contents. Each entry SHALL be rendered into the etc-overlay alongside the chart-managed `.cfg` files.

#### Scenario: User-provided file lands in etc-overlay

- **WHEN** the chart is installed with `extraConfigFiles."org.opennms.example.cfg"="key=value"`
- **THEN** the rendered etc-overlay ConfigMap contains a key whose path corresponds to `org.opennms.example.cfg`
- **AND** the contents of that key equal `key=value`
