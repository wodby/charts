{{/* Return the proper image name. */}}
{{- define "frps.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/* Expand the chart name. */}}
{{- define "frps.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a fully qualified application name. */}}
{{- define "frps.fullname" -}}
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

{{/* Create chart labels. */}}
{{- define "frps.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "frps.selectorLabels" -}}
app.kubernetes.io/name: {{ include "frps.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "frps.labels" -}}
helm.sh/chart: {{ include "frps.chart" . }}
{{ include "frps.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Return image pull secrets. */}}
{{- define "frps.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) }}
{{- end -}}

{{/* Return the Secret containing FRPS credentials. */}}
{{- define "frps.secretName" -}}
{{- if .Values.existingSecret -}}
{{- tpl .Values.existingSecret $ -}}
{{- else -}}
{{- printf "%s-auth" (include "frps.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/* Validate security-sensitive values. */}}
{{- define "frps.validateValues" -}}
{{- if and .Values.existingSecret (or .Values.auth.token .Values.webServer.password) -}}
{{- fail "Use either existingSecret or auth.token/webServer.password, not both" -}}
{{- end -}}
{{- if and (not .Values.existingSecret) (not .Values.auth.token) -}}
{{- fail "Set auth.token or existingSecret" -}}
{{- end -}}
{{- if and (not .Values.existingSecret) (not .Values.webServer.password) -}}
{{- fail "Set webServer.password or existingSecret" -}}
{{- end -}}
{{- if not .Values.webServer.user -}}
{{- fail "Set webServer.user" -}}
{{- end -}}
{{- end -}}
