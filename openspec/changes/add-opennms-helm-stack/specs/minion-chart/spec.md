## ADDED Requirements

### Requirement: Minion image source and version pinning

The `minion` chart SHALL deploy OpenNMS Minion from the upstream image `docker.io/opennms/minion`. The chart's `Chart.yaml` SHALL declare `appVersion: "35.0.5"`. The default `image.tag` value SHALL be the empty string, and the StatefulSet template SHALL fall through to `.Chart.AppVersion` when `image.tag` is unset.

#### Scenario: Default install pins the tested image tag

- **WHEN** a user runs `helm install minion-nyc charts/minion` without overriding `image.tag`
- **THEN** the rendered StatefulSet uses image `docker.io/opennms/minion:35.0.5`

### Requirement: Minion deploys as a StatefulSet without HPA

The `minion` chart SHALL deploy Minion as a `StatefulSet`. The chart SHALL NOT include a `HorizontalPodAutoscaler` template. The default `replicaCount` SHALL be `1`.

#### Scenario: Default workload kind is StatefulSet

- **WHEN** the chart is installed with default values
- **THEN** the resulting workload kind is `StatefulSet` with `spec.replicas: 1`

#### Scenario: No HPA resource exists

- **WHEN** the chart is rendered with any combination of values
- **THEN** no `HorizontalPodAutoscaler` resource appears in the output

### Requirement: Minion identity from downward API + envsubst

The `minion` chart SHALL inject `MINION_ID` from the pod's `metadata.name` via the downward API and `MINION_LOCATION` from `.Values.location`. An `envsubst` initContainer SHALL substitute these values into `org.opennms.minion.controller.cfg` written to an `emptyDir` volume mounted at `/opt/minion-etc-overlay/etc/`.

#### Scenario: Pod gets unique stable id

- **WHEN** the chart is installed with `replicaCount: 2` and `location: nyc` for release named `minion-nyc`
- **THEN** pod `minion-nyc-0` has `MINION_ID=minion-nyc-0` and pod `minion-nyc-1` has `MINION_ID=minion-nyc-1`
- **AND** both pods have `MINION_LOCATION=nyc`

#### Scenario: Controller cfg rendered with placeholders

- **WHEN** the chart renders templates
- **THEN** the ConfigMap contains a template for `org.opennms.minion.controller.cfg` with `id=${MINION_ID}` and `location=${MINION_LOCATION}`

### Requirement: Minion configures Kafka via etc-overlay

The `minion` chart SHALL render `org.opennms.core.ipc.sink.kafka.cfg`, `org.opennms.core.ipc.rpc.kafka.cfg`, and `org.opennms.core.ipc.twin.kafka.cfg` into the etc-overlay, each carrying the same `bootstrap.servers` value from `kafka.bootstrapServers`. The chart SHALL also render `instance-id.properties` containing the value of `instanceId` (default `OpenNMS`). The chart SHALL also render the boot-feature files `kafka-ipc.boot`, `kafka-rpc.boot`, `kafka-sink.boot`, and `kafka-twin.boot` to enable the Kafka strategies. The chart SHALL NOT support ActiveMQ or any non-Kafka broker.

#### Scenario: Three Kafka cfg files rendered with same brokers

- **WHEN** the chart is installed with `kafka.bootstrapServers: "k1:9092,k2:9092"`
- **THEN** the etc-overlay contains all three `org.opennms.core.ipc.{sink,rpc,twin}.kafka.cfg` files
- **AND** each file contains `bootstrap.servers=k1:9092,k2:9092`

#### Scenario: Kafka boot files enable Kafka strategy

- **WHEN** the chart renders templates
- **THEN** the etc-overlay contains `kafka-ipc.boot`, `kafka-rpc.boot`, `kafka-sink.boot`, and `kafka-twin.boot`

### Requirement: Mixed-content .cfg files use envsubst initContainer

When a rendered Minion `.cfg` file contains both non-secret values and references to credentials from a Secret (Kafka SASL credentials, Dominion gRPC client secret), the chart SHALL use the same envsubst initContainer pattern as Core: ConfigMap with `${VAR}` placeholders + Secret env-var refs + initContainer that writes resolved files to an `emptyDir` mounted at the etc-overlay path.

#### Scenario: Kafka SASL password substituted at pod start

- **WHEN** the chart is installed with `kafka.auth.enabled: true` and `kafka.auth.existingSecret: minion-kafka`
- **THEN** the pod spec contains an initContainer that mounts the placeholder ConfigMap and `minion-kafka`
- **AND** the resulting Kafka cfg files in `/opt/minion-etc-overlay/etc/` contain the resolved password (not `${KAFKA_PASSWORD}`)

### Requirement: Confd is left inert

The `minion` chart SHALL mount an empty (`{}`) `minion-config.yaml` at `/opt/minion/minion-config.yaml`. The chart SHALL NOT populate that file with non-empty configuration.

#### Scenario: Confd YAML overlay is empty

- **WHEN** the chart renders templates
- **THEN** the file mounted at `/opt/minion/minion-config.yaml` parses as the empty YAML object `{}`

### Requirement: Per-replica persistent state

The `minion` chart SHALL provide a `volumeClaimTemplates` entry mounted at `/opt/minion/data` when `persistence.enabled` is `true`. The default size SHALL be `1Gi`, the default `accessMode` SHALL be `ReadWriteOnce`, and the default `storageClassName` SHALL be unset.

#### Scenario: Per-pod PVC at default size

- **WHEN** the chart is installed with `replicaCount: 2` and default persistence
- **THEN** two PersistentVolumeClaims are created (one per pod) each with `requests.storage: 1Gi` mounted at `/opt/minion/data`

#### Scenario: Persistence can be disabled

- **WHEN** the chart is installed with `persistence.enabled: false`
- **THEN** no `volumeClaimTemplate` is rendered
- **AND** `/opt/minion/data` is mounted as `emptyDir`

### Requirement: Minion does not deploy infrastructure

The `minion` chart SHALL NOT deploy Kafka or any other infrastructure under any combination of values.

#### Scenario: Rendered chart contains no infrastructure workloads

- **WHEN** the chart is rendered with any values
- **THEN** no workload for Kafka, ZooKeeper, Postgres, or Elasticsearch appears in the output

### Requirement: ServiceAccount creation

The `minion` chart SHALL render a `ServiceAccount` resource when `serviceAccount.create` is `true` (the default). The ServiceAccount's name SHALL match the value the StatefulSet's `serviceAccountName` field resolves to.

#### Scenario: Default install creates a ServiceAccount

- **WHEN** the chart is installed with default values
- **THEN** the rendered output contains a `ServiceAccount` resource
- **AND** the StatefulSet's `spec.template.spec.serviceAccountName` matches the rendered ServiceAccount's `metadata.name`

#### Scenario: ServiceAccount creation can be disabled

- **WHEN** the chart is installed with `serviceAccount.create: false` and `serviceAccount.name: my-existing-sa`
- **THEN** no `ServiceAccount` resource is rendered by the chart
- **AND** the StatefulSet's `spec.template.spec.serviceAccountName` equals `my-existing-sa`

### Requirement: Minion is independent of opennms-stack

The `minion` chart SHALL NOT be declared as a subchart dependency of `opennms-stack`. The `minion` chart SHALL be installable only as a standalone Helm release.

#### Scenario: Umbrella does not pull in Minion

- **WHEN** the `opennms-stack` umbrella is rendered with default values
- **THEN** no Minion resources appear in the output
- **AND** `opennms-stack/Chart.yaml` does not list `minion` in its `dependencies`
