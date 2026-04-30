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
Postgres existingSecret — resolves global vs local. Empty string means the
chart will render a lab-mode Secret instead.
*/}}
{{- define "core.postgresExistingSecret" -}}
{{- $global := ((((.Values.global).postgresql).auth).existingSecret) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.postgresql.auth.existingSecret }}{{- end -}}
{{- end }}

{{/*
Returns the Secret name to use for Postgres credentials. Either the user's
existingSecret or the chart-managed lab-mode Secret.
*/}}
{{- define "core.postgresSecretName" -}}
{{- $existing := include "core.postgresExistingSecret" . -}}
{{- if $existing -}}{{ $existing }}{{- else -}}{{ include "core.fullname" . }}-credentials{{- end -}}
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
Kafka .cfg body shared by sink, rpc, and twin .cfg files. Emits bootstrap.servers,
security.protocol, optional SASL block (with envsubst placeholders for credentials),
and any extraProperties.
*/}}
{{- define "core.kafkaCfgBlock" -}}
bootstrap.servers={{ include "core.kafkaBootstrap" . }}
security.protocol={{ include "core.kafkaSecurityProtocol" . }}
{{- if .Values.kafka.auth.enabled }}
sasl.mechanism={{ .Values.kafka.auth.mechanism }}
sasl.jaas.config={{ include "core.kafkaJaasModule" . }} required username="${KAFKA_USERNAME}" password="${KAFKA_PASSWORD}";
{{- end }}
{{- range $k, $v := .Values.kafka.extraProperties }}
{{ $k }}={{ $v }}
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
      apk add --no-cache gettext >/dev/null 2>&1 || true
      # ConfigMap data keys cannot contain "/", so subpaths under etc/ are
      # encoded with "__" in the key name and decoded back to "/" here.
      # Example: opennms.properties.d__timeseries.properties
      #          → etc/opennms.properties.d/timeseries.properties
      for tmpl in /tmp/templates/*; do
        [ -f "$tmpl" ] || continue
        rel="$(basename "$tmpl" | sed 's|__|/|g')"
        out="/etc-overlay/etc/$rel"
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
{{- if and .Values.elasticsearch.enabled .Values.elasticsearch.auth.existingSecret }}
- name: ELASTIC_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.elasticsearch.auth.existingSecret | quote }}
      key: ELASTIC_USERNAME
- name: ELASTIC_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.elasticsearch.auth.existingSecret | quote }}
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
