## ADDED Requirements

### Requirement: Sentinel image source and version pinning

The `sentinel` chart SHALL deploy OpenNMS Sentinel from the upstream image `docker.io/opennms/sentinel`. The chart's `Chart.yaml` SHALL declare `appVersion: "35.0.5"`. The default `image.tag` value SHALL be the empty string, and the workload template SHALL fall through to `.Chart.AppVersion` when `image.tag` is unset.

#### Scenario: Default install pins the tested image tag

- **WHEN** a user installs the chart without overriding `image.tag`
- **THEN** the rendered workload uses image `docker.io/opennms/sentinel:35.0.5`

### Requirement: Sentinel deploys as a horizontally scalable Deployment

The `sentinel` chart SHALL deploy Sentinel as a `Deployment`, NOT a StatefulSet. The chart SHALL expose a `HorizontalPodAutoscaler` template gated by `autoscaling.enabled`. The default `replicaCount` SHALL be `1`.

#### Scenario: Default deployment shape

- **WHEN** the chart is installed with default values
- **THEN** the resulting workload kind is `Deployment` with `spec.replicas: 1`

#### Scenario: HPA can be enabled

- **WHEN** the chart is installed with `autoscaling.enabled: true`, `autoscaling.minReplicas: 2`, and `autoscaling.maxReplicas: 5`
- **THEN** a `HorizontalPodAutoscaler` resource is rendered with those bounds targeting the Deployment

### Requirement: Sentinel connects to BYO Postgres via etc-overlay

The `sentinel` chart SHALL render Sentinel's distributed-datasource config (`org.opennms.netmgt.distributed.datasource.cfg`) into the etc-overlay when `postgresql.auth.existingSecret` (or its `global` umbrella equivalent) is set. The file SHALL contain `datasource.url`, `datasource.username`, `datasource.password`, and `datasource.databaseName` derived from the chart's `postgresql.*` values. The username and password values SHALL be substituted at pod start by the `envsubst` initContainer reading from the referenced Secret. The chart's username/password env-var contract SHALL match Core's so a single Postgres Secret covers both subcharts under the umbrella.

#### Scenario: Datasource cfg is rendered with placeholders

- **WHEN** the chart is installed with `postgresql.host: postgres.db.svc.cluster.local`, `postgresql.database: opennms`, and `postgresql.auth.existingSecret: opennms-postgres`
- **THEN** a ConfigMap contains a template for `org.opennms.netmgt.distributed.datasource.cfg` containing the host and database name as literals
- **AND** the username line is `datasource.username=${OPENNMS_DBUSER}` and the password line is `datasource.password=${OPENNMS_DBPASS}` (placeholders)
- **AND** the initContainer mounts `opennms-postgres` and exposes `OPENNMS_DBUSER` and `OPENNMS_DBPASS` as env vars

### Requirement: Sentinel configures Kafka via etc-overlay

The `sentinel` chart SHALL render at minimum `org.opennms.core.ipc.sink.kafka.cfg` into the etc-overlay carrying `kafka.bootstrapServers`. The chart SHALL also render `instance-id.properties` containing the value of `instanceId` (default `OpenNMS`). The chart SHALL NOT support ActiveMQ or any non-Kafka broker.

#### Scenario: Sink Kafka cfg contains bootstrap servers

- **WHEN** the chart is installed with `kafka.bootstrapServers: "k1:9092,k2:9092"`
- **THEN** the rendered etc-overlay contains `org.opennms.core.ipc.sink.kafka.cfg` with `bootstrap.servers=k1:9092,k2:9092`

### Requirement: Sentinel connects to BYO Elasticsearch via etc-overlay

The `sentinel` chart SHALL render `org.opennms.features.flows.persistence.elastic.cfg` into the etc-overlay. The file SHALL contain `elasticUrl`, `elasticIndexStrategy`, and `settings.index.number_of_replicas` derived from the chart's `elasticsearch.*` values. When `elasticsearch.auth.existingSecret` is set, basic-auth credentials SHALL be substituted via the `envsubst` initContainer.

#### Scenario: Elasticsearch URL and strategy land in cfg file

- **WHEN** the chart is installed with `elasticsearch.url: "http://es.example:9200"` and `elasticsearch.indexStrategy: monthly`
- **THEN** the rendered etc-overlay contains `org.opennms.features.flows.persistence.elastic.cfg` with `elasticUrl=http://es.example:9200`
- **AND** the same file contains `elasticIndexStrategy=monthly`

### Requirement: Sentinel SCV credentials via env vars

The `sentinel` chart SHALL pass OpenNMS HTTP and broker credentials to the container as environment variables (`OPENNMS_HTTP_USER`, `OPENNMS_HTTP_PASS`, `OPENNMS_BROKER_USER`, `OPENNMS_BROKER_PASS`) sourced from referenced Secrets so the entrypoint can register them in the SCV keystore.

#### Scenario: SCV credentials wired from existingSecret

- **WHEN** the chart is installed with `opennms.http.existingSecret: onms-http` and `opennms.broker.existingSecret: onms-broker`
- **THEN** the container's `env` includes four entries (`OPENNMS_HTTP_USER`, `OPENNMS_HTTP_PASS`, `OPENNMS_BROKER_USER`, `OPENNMS_BROKER_PASS`) sourced via `valueFrom.secretKeyRef`

### Requirement: Confd is left inert

The `sentinel` chart SHALL mount an empty (`{}`) `sentinel-config.yaml` at `/opt/sentinel/sentinel-config.yaml`. The chart SHALL NOT populate that file with non-empty configuration.

#### Scenario: Confd YAML overlay is empty

- **WHEN** the chart renders templates
- **THEN** the file mounted at `/opt/sentinel/sentinel-config.yaml` parses as the empty YAML object `{}`

### Requirement: Sentinel does not deploy infrastructure

The `sentinel` chart SHALL NOT deploy Postgres, Kafka, or Elasticsearch under any combination of values.

#### Scenario: Rendered chart contains no infrastructure workloads

- **WHEN** the chart is rendered with any values
- **THEN** no workload, StatefulSet, or Deployment for Postgres, Kafka, ZooKeeper, or Elasticsearch appears in the output

### Requirement: ServiceAccount creation

The `sentinel` chart SHALL render a `ServiceAccount` resource when `serviceAccount.create` is `true` (the default). The ServiceAccount's name SHALL match the value the Deployment's `serviceAccountName` field resolves to.

#### Scenario: Default install creates a ServiceAccount

- **WHEN** the chart is installed with default values
- **THEN** the rendered output contains a `ServiceAccount` resource
- **AND** the Deployment's `spec.template.spec.serviceAccountName` matches the rendered ServiceAccount's `metadata.name`

#### Scenario: ServiceAccount creation can be disabled

- **WHEN** the chart is installed with `serviceAccount.create: false` and `serviceAccount.name: my-existing-sa`
- **THEN** no `ServiceAccount` resource is rendered by the chart
- **AND** the Deployment's `spec.template.spec.serviceAccountName` equals `my-existing-sa`

### Requirement: Sentinel installable standalone or as a subchart

The `sentinel` chart SHALL be a fully self-contained Helm chart that produces a working release when installed directly with `helm install`. The chart SHALL also be valid as a subchart of `opennms-stack`, reading shared values from `.Values.global.*` when present and falling back to its own values when not.

#### Scenario: Standalone install produces a working release

- **WHEN** a user runs `helm install sent charts/sentinel` with required values for `postgresql`, `kafka`, and `elasticsearch`
- **THEN** the install succeeds without referencing the umbrella

#### Scenario: Subchart install reads global values

- **WHEN** the umbrella sets `global.kafka.bootstrapServers: "k1:9092"` and the user does not set `sentinel.kafka.bootstrapServers`
- **THEN** the rendered Sentinel etc-overlay contains `bootstrap.servers=k1:9092`
