{{/*
Expand the name of the chart.
*/}}
{{- define "sentinel.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "sentinel.fullname" -}}
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

{{- define "sentinel.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "sentinel.labels" -}}
helm.sh/chart: {{ include "sentinel.chart" . }}
app.opennms.org/component: sentinel
{{ include "sentinel.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "sentinel.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sentinel.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "sentinel.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "sentinel.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image reference. tag falls through to .Chart.AppVersion when unset.
*/}}
{{- define "sentinel.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end }}

{{/*
Resolve global vs local values. When Sentinel is installed under the
opennms-stack umbrella, .Values.global.* takes precedence over the local key.
*/}}
{{- define "sentinel.kafkaBootstrap" -}}
{{- $global := (((.Values.global).kafka).bootstrapServers) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.kafka.bootstrapServers }}{{- end -}}
{{- end }}

{{- define "sentinel.instanceId" -}}
{{- $global := ((.Values.global).instanceId) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.instanceId }}{{- end -}}
{{- end }}

{{- define "sentinel.postgresHost" -}}
{{- $global := (((.Values.global).postgresql).host) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.postgresql.host }}{{- end -}}
{{- end }}

{{- define "sentinel.postgresPort" -}}
{{- $global := (((.Values.global).postgresql).port) | default 0 -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.postgresql.port }}{{- end -}}
{{- end }}

{{- define "sentinel.postgresDatabase" -}}
{{- $global := (((.Values.global).postgresql).database) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.postgresql.database }}{{- end -}}
{{- end }}

{{- define "sentinel.postgresExistingSecret" -}}
{{- $global := ((((.Values.global).postgresql).auth).existingSecret) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.postgresql.auth.existingSecret }}{{- end -}}
{{- end }}

{{- define "sentinel.elasticsearchUrl" -}}
{{- $global := (((.Values.global).elasticsearch).url) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.elasticsearch.url }}{{- end -}}
{{- end }}

{{- define "sentinel.elasticsearchExistingSecret" -}}
{{- $global := ((((.Values.global).elasticsearch).auth).existingSecret) | default "" -}}
{{- if $global -}}{{ $global }}{{- else -}}{{ .Values.elasticsearch.auth.existingSecret }}{{- end -}}
{{- end }}

{{/*
Kafka SASL JAAS module class for the configured mechanism.
*/}}
{{- define "sentinel.kafkaJaasModule" -}}
{{- $mech := .Values.kafka.auth.mechanism -}}
{{- if eq $mech "PLAIN" -}}org.apache.kafka.common.security.plain.PlainLoginModule{{- else -}}org.apache.kafka.common.security.scram.ScramLoginModule{{- end -}}
{{- end }}

{{- define "sentinel.kafkaSecurityProtocol" -}}
{{- if and .Values.kafka.auth.enabled .Values.kafka.tls.enabled -}}SASL_SSL
{{- else if .Values.kafka.auth.enabled -}}SASL_PLAINTEXT
{{- else if .Values.kafka.tls.enabled -}}SSL
{{- else -}}PLAINTEXT
{{- end -}}
{{- end }}

{{/*
Kafka .cfg body. Sentinel only consumes the sink (it doesn't run RPC or twin),
but the .cfg file shape matches Core's. Emits bootstrap.servers,
security.protocol, optional SASL block, and any extraProperties.
*/}}
{{- define "sentinel.kafkaCfgBlock" -}}
bootstrap.servers={{ include "sentinel.kafkaBootstrap" . }}
security.protocol={{ include "sentinel.kafkaSecurityProtocol" . }}
{{- if .Values.kafka.auth.enabled }}
sasl.mechanism={{ .Values.kafka.auth.mechanism }}
sasl.jaas.config={{ include "sentinel.kafkaJaasModule" . }} required username="${KAFKA_USERNAME}" password="${KAFKA_PASSWORD}";
{{- end }}
{{- range $k, $v := .Values.kafka.extraProperties }}
{{ $k }}={{ $v }}
{{- end }}
{{- end }}

{{/*
envsubst initContainer for rendering placeholder .cfg files into the
etc-overlay emptyDir. Subpath encoding: "__" in the ConfigMap key name is
decoded to "/" at render time so files can land in subdirectories under etc/.

This helper is duplicated in core/ and minion/ — keep them in sync.
*/}}
{{- define "sentinel.envsubstInitContainer" -}}
{{- $envContent := include "sentinel.envsubstEnv" . | trim -}}
- name: render-config
  image: "{{ .Values.configRenderer.image.repository }}:{{ .Values.configRenderer.image.tag }}"
  imagePullPolicy: {{ .Values.configRenderer.image.pullPolicy | quote }}
  command:
    - /bin/sh
    - -c
    - |
      set -eu
      apk add --no-cache gettext >/dev/null
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
Env vars for the envsubst init: Postgres credentials (always when
existingSecret is set), Kafka SASL (when enabled), Elasticsearch (when set).
*/}}
{{- define "sentinel.envsubstEnv" -}}
{{- $pgSecret := include "sentinel.postgresExistingSecret" . -}}
{{- if $pgSecret }}
- name: OPENNMS_DBUSER
  valueFrom:
    secretKeyRef:
      name: {{ $pgSecret | quote }}
      key: OPENNMS_DBUSER
- name: OPENNMS_DBPASS
  valueFrom:
    secretKeyRef:
      name: {{ $pgSecret | quote }}
      key: OPENNMS_DBPASS
{{- end }}
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
{{- $esSecret := include "sentinel.elasticsearchExistingSecret" . -}}
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
{{- end }}

{{/*
Env vars for the runtime container that drive the Sentinel entrypoint:
- SENTINEL_LOCATION: written by entrypoint into controller.cfg
- OPENNMS_HTTP_USER/PASS, OPENNMS_BROKER_USER/PASS: stored in SCV keystore
  by the entrypoint's `-c` mode at startup
The instance ID is rendered into instance-id.properties via the etc-overlay,
not via env var.
*/}}
{{- define "sentinel.runtimeEnv" -}}
- name: SENTINEL_LOCATION
  value: {{ .Values.location | quote }}
{{- if .Values.javaOpts }}
- name: JAVA_OPTS
  value: {{ .Values.javaOpts | quote }}
{{- end }}
{{- if .Values.prometheus.jmxExporter.enabled }}
- name: PROM_JMX_EXPORTER_ENABLED
  value: "true"
- name: PROM_JMX_EXPORTER_PORT
  value: {{ .Values.prometheus.jmxExporter.port | quote }}
{{- end }}
{{- if .Values.opennms.http.existingSecret }}
- name: OPENNMS_HTTP_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.opennms.http.existingSecret | quote }}
      key: OPENNMS_HTTP_USER
- name: OPENNMS_HTTP_PASS
  valueFrom:
    secretKeyRef:
      name: {{ .Values.opennms.http.existingSecret | quote }}
      key: OPENNMS_HTTP_PASS
{{- end }}
{{- if .Values.opennms.broker.existingSecret }}
- name: OPENNMS_BROKER_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.opennms.broker.existingSecret | quote }}
      key: OPENNMS_BROKER_USER
- name: OPENNMS_BROKER_PASS
  valueFrom:
    secretKeyRef:
      name: {{ .Values.opennms.broker.existingSecret | quote }}
      key: OPENNMS_BROKER_PASS
{{- end }}
{{- end }}

{{/*
Sentinel's startup arg. Use `-c` when SCV credentials are sourced from env
vars, `-f` otherwise (lab mode without auth).
*/}}
{{- define "sentinel.startupArg" -}}
{{- if or .Values.opennms.http.existingSecret .Values.opennms.broker.existingSecret -}}-c{{- else -}}-f{{- end -}}
{{- end }}
