## ADDED Requirements

### Requirement: Umbrella name and chart layout

The umbrella chart SHALL be named `opennms-stack` and live at `charts/opennms-stack/`. Its `Chart.yaml` SHALL declare `apiVersion: v2`, `type: application`, `name: opennms-stack`, and an `appVersion` matching the subcharts' `appVersion` (`"35.0.5"`).

#### Scenario: Chart name and type

- **WHEN** `helm show chart charts/opennms-stack` is run
- **THEN** the output shows `name: opennms-stack`, `type: application`, and `appVersion: "35.0.5"`

### Requirement: Umbrella bundles Core and Sentinel only

The `opennms-stack` chart SHALL declare `core` and `sentinel` as subchart dependencies in `Chart.yaml`. The umbrella SHALL NOT declare `minion` as a subchart dependency under any condition.

#### Scenario: Dependencies list includes core and sentinel

- **WHEN** `Chart.yaml` is parsed
- **THEN** the `dependencies` array contains exactly two entries with `name: core` and `name: sentinel`

#### Scenario: Default install renders Core and Sentinel resources

- **WHEN** `helm template stack charts/opennms-stack` is run with default values
- **THEN** the output contains a `StatefulSet` for Core and a `Deployment` for Sentinel
- **AND** the output contains no Minion resources

### Requirement: Subchart versions are strict-pinned

The `opennms-stack/Chart.yaml` `dependencies` block SHALL pin each subchart with an exact version constraint (e.g., `version: =0.3.2`), not a range (`~`, `^`, or open-ended). The umbrella's `version` field SHALL be bumped whenever any pinned subchart version changes.

#### Scenario: Dependency version uses exact pin

- **WHEN** `Chart.yaml` is parsed
- **THEN** each entry in `dependencies` has a `version` field that begins with `=` (or is otherwise a single non-range version constraint)

### Requirement: Umbrella exposes shared values via global

The `opennms-stack` chart SHALL define a `global` block in its `values.yaml` containing `global.instanceId`, `global.kafka.bootstrapServers`, `global.kafka.auth`, `global.kafka.tls`, `global.postgresql`, and `global.elasticsearch`. Subcharts SHALL prefer values under `.Values.global.*` over their own values when both are set, via a helper template that defaults the local value to the global one.

#### Scenario: Global Kafka brokers override subchart defaults

- **WHEN** the umbrella is installed with `global.kafka.bootstrapServers: "k1:9092"` and no `core.kafka.bootstrapServers` override
- **THEN** the rendered Core etc-overlay contains `bootstrap.servers=k1:9092` (sourced from the global)

#### Scenario: Subchart-local override wins

- **WHEN** the umbrella is installed with `global.kafka.bootstrapServers: "k1:9092"` and `core.kafka.bootstrapServers: "kalt:9092"`
- **THEN** the rendered Core etc-overlay contains `bootstrap.servers=kalt:9092`

### Requirement: Umbrella does not deploy infrastructure

The `opennms-stack` chart SHALL NOT deploy Postgres, Kafka, Elasticsearch, or any other infrastructure under any combination of values.

#### Scenario: Rendered umbrella contains no infrastructure workloads

- **WHEN** `helm template` is run with any values
- **THEN** no workload, StatefulSet, or Deployment for Postgres, Kafka, ZooKeeper, or Elasticsearch appears in the output

### Requirement: Subchart toggles

The `opennms-stack` chart SHALL allow disabling Sentinel via `sentinel.enabled: false` in values. Core SHALL always render (it is the central concern of the umbrella).

#### Scenario: Sentinel can be turned off

- **WHEN** the umbrella is installed with `sentinel.enabled: false`
- **THEN** no Sentinel resources are rendered
- **AND** Core resources are rendered as normal

### Requirement: Standalone subcharts remain independently installable

When a subchart (`core` or `sentinel`) is installed directly (not through `opennms-stack`), the chart SHALL function correctly without requiring `global.*` values to be defined.

#### Scenario: Core installs standalone without global

- **WHEN** `helm install onms charts/core` is run with all required local values set
- **THEN** the install succeeds
- **AND** the helper template that resolves `bootstrap.servers` returns the local value
