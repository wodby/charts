{{/*
Return the proper image name
*/}}
{{- define "mtproxy.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Expand the name of the chart.
*/}}
{{- define "mtproxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "mtproxy.fullname" -}}
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
{{- define "mtproxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mtproxy.labels" -}}
helm.sh/chart: {{ include "mtproxy.chart" . }}
{{ include "mtproxy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mtproxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mtproxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "mtproxy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mtproxy.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "mtproxy.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) }}
{{- end -}}

{{/*
Return true if a secret object should be created.
*/}}
{{- define "mtproxy.createSecret" -}}
{{- if and (not .Values.existingSecret) (or .Values.config.secrets .Values.config.tag) -}}
{{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return the secret with MTProxy configuration.
*/}}
{{- define "mtproxy.secretName" -}}
{{- if .Values.existingSecret -}}
{{- printf "%s" (tpl .Values.existingSecret $) -}}
{{- else -}}
{{- printf "%s-config" (include "mtproxy.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Validate values that can break MTProxy startup.
*/}}
{{- define "mtproxy.validateValues" -}}
{{- if and .Values.existingSecret (or .Values.config.secrets .Values.config.tag) -}}
{{- fail "Use either existingSecret or config.secrets/config.tag, not both" -}}
{{- end -}}
{{- if gt (len .Values.config.secrets) 16 -}}
{{- fail "config.secrets supports at most 16 entries" -}}
{{- end -}}
{{- if and (not .Values.existingSecret) (eq (len .Values.config.secrets) 0) -}}
{{- fail "Set config.secrets or existingSecret; the chart no longer provisions persistent storage for auto-generated secrets" -}}
{{- end -}}
{{- range $index, $secret := .Values.config.secrets -}}
{{- if not (regexMatch "^[0-9a-fA-F]{32}$" $secret) -}}
{{- fail (printf "config.secrets[%d] must be 32 hex characters" $index) -}}
{{- end -}}
{{- end -}}
{{- if and .Values.config.tag (not (regexMatch "^[0-9a-fA-F]{32}$" .Values.config.tag)) -}}
{{- fail "config.tag must be 32 hex characters" -}}
{{- end -}}
{{- if lt (int .Values.config.workers) 1 -}}
{{- fail "config.workers must be greater than 0" -}}
{{- end -}}
{{- end -}}
