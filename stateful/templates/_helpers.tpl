{{/*
Return the proper image name.
*/}}
{{- define "stateful.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global "chart" .Chart) }}
{{- end -}}

{{/*
Expand the name of the chart.
*/}}
{{- define "stateful.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "stateful.fullname" -}}
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
{{- define "stateful.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "stateful.labels" -}}
helm.sh/chart: {{ include "stateful.chart" . }}
{{ include "stateful.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "stateful.selectorLabels" -}}
app.kubernetes.io/name: {{ include "stateful.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "stateful.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "stateful.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper Docker Image Registry Secret Names.
*/}}
{{- define "stateful.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) }}
{{- end -}}

{{/*
Create the name of the headless service.
*/}}
{{- define "stateful.headlessServiceName" -}}
{{- default (printf "%s-headless" (include "stateful.fullname" .)) .Values.headlessService.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the service name used by the StatefulSet.
*/}}
{{- define "stateful.serviceName" -}}
{{- if .Values.headlessService.enabled }}
{{- include "stateful.headlessServiceName" . }}
{{- else }}
{{- include "stateful.fullname" . }}
{{- end }}
{{- end }}
