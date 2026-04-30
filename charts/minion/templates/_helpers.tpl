{{/*
Minion is intentionally NOT a subchart of opennms-stack — it deploys per
remote location, on a different release lifecycle than the central site.
Helpers here therefore read directly from `.Values.*` with no `global.*`
fall-through, unlike core/ and sentinel/ which support both standalone
and umbrella installation.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "minion.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "minion.fullname" -}}
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

{{- define "minion.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "minion.labels" -}}
helm.sh/chart: {{ include "minion.chart" . }}
app.opennms.org/component: minion
{{ include "minion.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "minion.selectorLabels" -}}
app.kubernetes.io/name: {{ include "minion.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "minion.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "minion.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image reference. tag falls through to .Chart.AppVersion when unset.
*/}}
{{- define "minion.image" -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end }}

{{/*
Kafka SASL JAAS module class for the configured mechanism.
*/}}
{{- define "minion.kafkaJaasModule" -}}
{{- $mech := .Values.kafka.auth.mechanism -}}
{{- if eq $mech "PLAIN" -}}org.apache.kafka.common.security.plain.PlainLoginModule{{- else -}}org.apache.kafka.common.security.scram.ScramLoginModule{{- end -}}
{{- end }}

{{- define "minion.kafkaSecurityProtocol" -}}
{{- if and .Values.kafka.auth.enabled .Values.kafka.tls.enabled -}}SASL_SSL
{{- else if .Values.kafka.auth.enabled -}}SASL_PLAINTEXT
{{- else if .Values.kafka.tls.enabled -}}SSL
{{- else -}}PLAINTEXT
{{- end -}}
{{- end }}

{{/*
Kafka .cfg body shared by sink, rpc, twin .cfg files.
*/}}
{{- define "minion.kafkaCfgBlock" -}}
bootstrap.servers={{ .Values.kafka.bootstrapServers }}
security.protocol={{ include "minion.kafkaSecurityProtocol" . }}
{{- if .Values.kafka.auth.enabled }}
sasl.mechanism={{ .Values.kafka.auth.mechanism }}
sasl.jaas.config={{ include "minion.kafkaJaasModule" . }} required username="${KAFKA_USERNAME}" password="${KAFKA_PASSWORD}";
{{- end }}
{{- range $k, $v := .Values.kafka.extraProperties }}
{{ $k }}={{ $v }}
{{- end }}
{{- end }}

{{/*
envsubst initContainer — same shape as core/sentinel. Decodes "__" to "/".
*/}}
{{- define "minion.envsubstInitContainer" -}}
{{- $envExtra := include "minion.envsubstEnv" . | trim -}}
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
  env:
    - name: MINION_ID
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: MINION_LOCATION
      value: {{ required "minion location is required (set .Values.location)" .Values.location | quote }}
    {{- if $envExtra }}
{{ $envExtra | indent 4 }}
    {{- end }}
  volumeMounts:
    - name: config-templates
      mountPath: /tmp/templates
    - name: etc-overlay
      mountPath: /etc-overlay
{{- end }}

{{- define "minion.envsubstEnv" -}}
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
{{- end }}

{{/*
Runtime container env. MINION_ID and MINION_LOCATION are the load-bearing
identity values; entrypoint reads them at startup.
*/}}
{{- define "minion.runtimeEnv" -}}
- name: MINION_ID
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: MINION_LOCATION
  value: {{ required "minion location is required (set .Values.location)" .Values.location | quote }}
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
Minion startup arg. `-c` when SCV credentials come from env, `-f` otherwise.
*/}}
{{- define "minion.startupArg" -}}
{{- if or .Values.opennms.http.existingSecret .Values.opennms.broker.existingSecret -}}-c{{- else -}}-f{{- end -}}
{{- end }}
