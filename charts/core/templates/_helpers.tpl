{{/*
Expand the name of the chart.
*/}}
{{- define "core.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "core.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "core.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "core.labels" -}}
helm.sh/chart: {{ include "core.chart" . }}
app.opennms.org/component: core
{{ include "core.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "core.selectorLabels" -}}
app.kubernetes.io/name: {{ include "core.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "core.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "core.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image reference. tag falls through to .Chart.AppVersion when unset.
*/}}
{{- define "core.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end }}

{{/*
Kafka bootstrap servers — resolves global vs local.
*/}}
{{- define "core.kafkaBootstrap" -}}
{{- $global := (((.Values.global).kafka).bootstrapServers) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.kafka.bootstrapServers }}{{- end -}}
{{- end }}

{{/*
Instance ID — resolves global vs local.
*/}}
{{- define "core.instanceId" -}}
{{- $global := ((.Values.global).instanceId) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.instanceId }}{{- end -}}
{{- end }}

{{/*
Postgres connectivity — resolves global vs local for each field.
*/}}
{{- define "core.postgresHost" -}}
{{- $global := (((.Values.global).postgresql).host) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.postgresql.host }}{{- end -}}
{{- end }}

{{- define "core.postgresPort" -}}
{{- $global := (((.Values.global).postgresql).port) | default 0 -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.postgresql.port }}{{- end -}}
{{- end }}

{{- define "core.postgresDatabase" -}}
{{- $global := (((.Values.global).postgresql).database) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.postgresql.database }}{{- end -}}
{{- end }}

{{/*
Elasticsearch connectivity — resolves global vs local. Mirrors the Sentinel
chart's pattern so global.elasticsearch.* flows into Core when its optional
flow-persistence path is enabled.
*/}}
{{- define "core.elasticsearchUrl" -}}
{{- $global := (((.Values.global).elasticsearch).url) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.elasticsearch.url }}{{- end -}}
{{- end }}

{{- define "core.elasticsearchExistingSecret" -}}
{{- $global := ((((.Values.global).elasticsearch).auth).existingSecret) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.elasticsearch.auth.existingSecret }}{{- end -}}
{{- end }}

{{/*
Postgres superuser Secret reference — global > local > lab-mode fallback.
The lab-mode Secret `<release>-opennms-pg-superuser` is rendered by
core-pg-superuser-credentials.yaml when both global and local names are empty.
Note: lab-mode Secret name is release-scoped (not chart-scoped) so Sentinel
under the umbrella can synthesise the same name from .Release.Name alone.
*/}}
{{- define "core.postgresSuperuserSecretName" -}}
{{- $global := (((((.Values.global).postgresql).auth).superuserSecret).name) | default "" -}}
{{- $local := (((.Values.postgresql.auth).superuserSecret).name) | default "" -}}
{{- if $global -}}{{ $global }}
{{- else if $local -}}{{ $local }}
{{- else -}}{{ printf "%s-opennms-pg-superuser" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}
{{- end }}

{{- define "core.postgresSuperuserUserKey" -}}
{{- $global := (((((.Values.global).postgresql).auth).superuserSecret).name) | default "" -}}
{{- $local := (((.Values.postgresql.auth).superuserSecret).name) | default "" -}}
{{- if $global -}}{{ (((((.Values.global).postgresql).auth).superuserSecret).userKey) | default "username" }}
{{- else if $local -}}{{ (((.Values.postgresql.auth).superuserSecret).userKey) | default "username" }}
{{- else -}}username
{{- end -}}
{{- end }}

{{- define "core.postgresSuperuserPasswordKey" -}}
{{- $global := (((((.Values.global).postgresql).auth).superuserSecret).name) | default "" -}}
{{- $local := (((.Values.postgresql.auth).superuserSecret).name) | default "" -}}
{{- if $global -}}{{ (((((.Values.global).postgresql).auth).superuserSecret).passwordKey) | default "password" }}
{{- else if $local -}}{{ (((.Values.postgresql.auth).superuserSecret).passwordKey) | default "password" }}
{{- else -}}password
{{- end -}}
{{- end }}

{{/*
Postgres app-role Secret reference — global > local > lab-mode fallback.
The lab-mode Secret `<release>-opennms-pg-app` is rendered by
core-pg-app-credentials.yaml when both global and local names are empty.
Note: lab-mode Secret name is release-scoped (not chart-scoped) so Sentinel
under the umbrella can synthesise the same name from .Release.Name alone.
*/}}
{{- define "core.postgresAppSecretName" -}}
{{- $global := (((((.Values.global).postgresql).auth).appSecret).name) | default "" -}}
{{- $local := (((.Values.postgresql.auth).appSecret).name) | default "" -}}
{{- if $global -}}{{ $global }}
{{- else if $local -}}{{ $local }}
{{- else -}}{{ printf "%s-opennms-pg-app" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end -}}
{{- end }}

{{- define "core.postgresAppUserKey" -}}
{{- $global := (((((.Values.global).postgresql).auth).appSecret).name) | default "" -}}
{{- $local := (((.Values.postgresql.auth).appSecret).name) | default "" -}}
{{- if $global -}}{{ (((((.Values.global).postgresql).auth).appSecret).userKey) | default "username" }}
{{- else if $local -}}{{ (((.Values.postgresql.auth).appSecret).userKey) | default "username" }}
{{- else -}}username
{{- end -}}
{{- end }}

{{- define "core.postgresAppPasswordKey" -}}
{{- $global := (((((.Values.global).postgresql).auth).appSecret).name) | default "" -}}
{{- $local := (((.Values.postgresql.auth).appSecret).name) | default "" -}}
{{- if $global -}}{{ (((((.Values.global).postgresql).auth).appSecret).passwordKey) | default "password" }}
{{- else if $local -}}{{ (((.Values.postgresql.auth).appSecret).passwordKey) | default "password" }}
{{- else -}}password
{{- end -}}
{{- end }}

{{/*
Returns "true" when no superuserSecret is configured and the chart should
render the lab-mode Secret `<release>-opennms-pg-superuser`. Returns ""
otherwise.
*/}}
{{- define "core.postgresSuperuserLabMode" -}}
{{- $global := (((((.Values.global).postgresql).auth).superuserSecret).name) | default "" -}}
{{- $local := (((.Values.postgresql.auth).superuserSecret).name) | default "" -}}
{{- if and (not $global) (not $local) -}}true{{- end -}}
{{- end }}

{{/*
Returns "true" when no appSecret is configured and the chart should render
the lab-mode Secret `<release>-opennms-pg-app`. Returns "" otherwise.
*/}}
{{- define "core.postgresAppLabMode" -}}
{{- $global := (((((.Values.global).postgresql).auth).appSecret).name) | default "" -}}
{{- $local := (((.Values.postgresql.auth).appSecret).name) | default "" -}}
{{- if and (not $global) (not $local) -}}true{{- end -}}
{{- end }}

{{/*
Four `env:` entries projecting the Postgres env vars Core expects, sourced
from superuserSecret and appSecret with operator-configurable key names.
Used at both consumption sites (init container and runtime container) in
statefulset.yaml.
*/}}
{{- define "core.postgresEnv" -}}
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "core.postgresSuperuserSecretName" . | quote }}
      key: {{ include "core.postgresSuperuserUserKey" . | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "core.postgresSuperuserSecretName" . | quote }}
      key: {{ include "core.postgresSuperuserPasswordKey" . | quote }}
- name: OPENNMS_DBUSER
  valueFrom:
    secretKeyRef:
      name: {{ include "core.postgresAppSecretName" . | quote }}
      key: {{ include "core.postgresAppUserKey" . | quote }}
- name: OPENNMS_DBPASS
  valueFrom:
    secretKeyRef:
      name: {{ include "core.postgresAppSecretName" . | quote }}
      key: {{ include "core.postgresAppPasswordKey" . | quote }}
{{- end }}

{{/*
Kafka SASL JAAS module class for the configured mechanism.
*/}}
{{- define "core.kafkaJaasModule" -}}
{{- $mech := .Values.kafka.auth.mechanism -}}
{{- if eq $mech "PLAIN" -}}org.apache.kafka.common.security.plain.PlainLoginModule{{- else -}}org.apache.kafka.common.security.scram.ScramLoginModule{{- end -}}
{{- end }}

{{/*
Kafka SASL security protocol — adjusts based on whether TLS is also enabled.
*/}}
{{- define "core.kafkaSecurityProtocol" -}}
{{- if and .Values.kafka.auth.enabled .Values.kafka.tls.enabled -}}SASL_SSL
{{- else if .Values.kafka.auth.enabled -}}SASL_PLAINTEXT
{{- else if .Values.kafka.tls.enabled -}}SSL
{{- else -}}PLAINTEXT
{{- end -}}
{{- end }}

{{/*
Kafka IPC system properties for opennms.properties.d/. Core reads Kafka client
config from system properties (not Karaf ConfigAdmin .cfg files): the
org.opennms.core.ipc.kafka.* prefix is stripped by OnmsKafkaConfigProvider
(opennms-project: core/ipc/common/kafka/.../OnmsKafkaConfigProvider.java) and
the remainder is fed to the Kafka client.
*/}}
{{- define "core.kafkaSysPropsBlock" -}}
org.opennms.core.ipc.strategy=kafka
org.opennms.core.ipc.kafka.bootstrap.servers={{ include "core.kafkaBootstrap" . }}
org.opennms.core.ipc.kafka.security.protocol={{ include "core.kafkaSecurityProtocol" . }}
{{- if .Values.kafka.auth.enabled }}
org.opennms.core.ipc.kafka.sasl.mechanism={{ .Values.kafka.auth.mechanism }}
org.opennms.core.ipc.kafka.sasl.jaas.config={{ include "core.kafkaJaasModule" . }} required username="${KAFKA_USERNAME}" password="${KAFKA_PASSWORD}";
{{- end }}
{{- range $k, $v := .Values.kafka.extraProperties }}
org.opennms.core.ipc.kafka.{{ $k }}={{ $v }}
{{- end }}
{{- end }}

{{/*
envsubst initContainer for rendering placeholder .cfg files into the
etc-overlay emptyDir. Mounts the config-templates ConfigMap at /tmp/templates
and the etc-overlay emptyDir at /etc-overlay/etc/.

Caller MUST also define matching volumes and volumeMounts on the runtime
container (see statefulset.yaml).

This helper is duplicated in sentinel/ and minion/ — keep them in sync.
*/}}
{{- define "core.envsubstInitContainer" -}}
{{- $envContent := include "core.envsubstEnv" . | trim -}}
- name: render-config
  image: "{{ .Values.configRenderer.image.repository }}:{{ .Values.configRenderer.image.tag }}"
  imagePullPolicy: {{ .Values.configRenderer.image.pullPolicy | quote }}
  command:
    - /bin/sh
    - -c
    - |
      set -eu
      apk add --no-cache gettext >/dev/null
      # ConfigMap data keys cannot contain "/", so subpaths under etc/ are
      # encoded with "__" in the key name and decoded back to "/" here.
      # Example: opennms.properties.d__timeseries.properties
      #          → opennms.properties.d/timeseries.properties
      #
      # The upstream entrypoint's applyOverlayConfig step does
      # `rsync -r ${OVERLAY_ETC}/* ${HOME}/etc/.` — files at the root of
      # the overlay volume land directly in etc/. Do NOT prefix `etc/` here
      # or files will end up double-nested at /opt/<comp>/etc/etc/...
      for tmpl in /tmp/templates/*; do
        [ -f "$tmpl" ] || continue
        rel="$(basename "$tmpl" | sed 's|__|/|g')"
        out="/etc-overlay/$rel"
        mkdir -p "$(dirname "$out")"
        envsubst < "$tmpl" > "$out"
      done
  {{- if $envContent }}
  env:
{{ $envContent | indent 4 }}
  {{- end }}
  volumeMounts:
    - name: config-templates
      mountPath: /tmp/templates
    - name: etc-overlay
      mountPath: /etc-overlay
{{- end }}

{{/*
Env vars passed to the envsubst init container. Sourced from the user's
existingSecret for Kafka SASL, Elasticsearch auth, and prometheus-remote-writer
auth when enabled.
*/}}
{{- define "core.envsubstEnv" -}}
{{- if and .Values.kafka.auth.enabled .Values.kafka.auth.existingSecret }}
- name: KAFKA_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.kafka.auth.existingSecret | quote }}
      key: KAFKA_USERNAME
- name: KAFKA_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.kafka.auth.existingSecret | quote }}
      key: KAFKA_PASSWORD
{{- end }}
{{- $esSecret := include "core.elasticsearchExistingSecret" . -}}
{{- if and .Values.elasticsearch.enabled $esSecret }}
- name: ELASTIC_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ $esSecret | quote }}
      key: ELASTIC_USERNAME
- name: ELASTIC_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $esSecret | quote }}
      key: ELASTIC_PASSWORD
{{- end }}
{{- if and .Values.prometheusRemoteWriter.enabled .Values.prometheusRemoteWriter.auth.existingSecret }}
- name: PRW_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.prometheusRemoteWriter.auth.existingSecret | quote }}
      key: PRW_USERNAME
- name: PRW_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.prometheusRemoteWriter.auth.existingSecret | quote }}
      key: PRW_PASSWORD
{{- end }}
{{- end }}

{{/*
Effective time-series strategy. "integration" when prometheusRemoteWriter is
enabled (which routes time-series through the plugin), else the user's value.
*/}}
{{- define "core.timeseriesStrategy" -}}
{{- if .Values.prometheusRemoteWriter.enabled -}}integration{{- else -}}{{ .Values.timeseriesStrategy }}{{- end -}}
{{- end }}

{{/*
Default URL to download the prometheus-remote-writer KAR. Override-able via
.Values.prometheusRemoteWriter.kar.url for air-gapped/mirrored environments.
*/}}
{{- define "core.prometheusRemoteWriterKarUrl" -}}
{{- $override := .Values.prometheusRemoteWriter.kar.url -}}
{{- if $override -}}
{{- $override -}}
{{- else -}}
{{- $v := .Values.prometheusRemoteWriter.version -}}
{{- printf "https://github.com/opennms-forge/prometheus-remote-writer/releases/download/v%s/prometheus-remote-writer-kar-%s.kar" $v $v -}}
{{- end -}}
{{- end }}
