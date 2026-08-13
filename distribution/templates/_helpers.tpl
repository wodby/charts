{{- define "distribution.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global "chart" .Chart) }}
{{- end -}}

{{- define "distribution.htpasswdImage" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.auth.htpasswd.helperImage "global" .Values.global "chart" .Chart) }}
{{- end -}}

{{- define "distribution.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "distribution.fullname" -}}
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

{{- define "distribution.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "distribution.labels" -}}
helm.sh/chart: {{ include "distribution.chart" . }}
{{ include "distribution.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "distribution.selectorLabels" -}}
app.kubernetes.io/name: {{ include "distribution.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "distribution.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "distribution.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "distribution.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image .Values.auth.htpasswd.helperImage) "context" $) }}
{{- end -}}

{{- define "distribution.persistenceClaim" -}}
{{- default (include "distribution.fullname" .) .Values.persistence.existingClaim }}
{{- end -}}
