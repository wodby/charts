{{/* Chart name, used for the app.kubernetes.io/name label. */}}
{{- define "zammad.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Base resource name. It leaves room for the longest component suffix (-railsserver). */}}
{{- define "zammad.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 50 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 50 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Resource name of a component. NGINX takes the base name, because it serves the app. */}}
{{- define "zammad.componentName" -}}
{{- if eq .name "nginx" -}}
{{ include "zammad.fullname" .root }}
{{- else -}}
{{ include "zammad.fullname" .root }}-{{ .name }}
{{- end -}}
{{- end -}}

{{- define "zammad.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "zammad.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zammad.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "zammad.labels" -}}
helm.sh/chart: {{ include "zammad.chart" . }}
{{ include "zammad.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "zammad.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "zammad.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "zammad.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global "chart" .Chart) }}
{{- end -}}

{{- define "zammad.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) }}
{{- end -}}

{{/* Environment defaults of a component. */}}
{{- define "zammad.defaultEnv" -}}
{{- $root := .root -}}
{{- $env := list -}}
{{- if eq .name "nginx" -}}
{{- $env = list
  (dict "name" "NGINX_PORT" "value" "8080")
  (dict "name" "NGINX_SERVER_SCHEME" "value" $root.Values.nginx.scheme)
  (dict "name" "NGINX_CLIENT_MAX_BODY_SIZE" "value" $root.Values.nginx.clientMaxBodySize)
  (dict "name" "ZAMMAD_RAILSSERVER_HOST" "value" (include "zammad.componentName" (dict "root" $root "name" "railsserver")))
  (dict "name" "ZAMMAD_RAILSSERVER_PORT" "value" "3000")
  (dict "name" "ZAMMAD_WEBSOCKET_HOST" "value" (include "zammad.componentName" (dict "root" $root "name" "websocket")))
  (dict "name" "ZAMMAD_WEBSOCKET_PORT" "value" "6042")
-}}
{{- else if eq .name "railsserver" -}}
{{- $env = list (dict "name" "ZAMMAD_RAILSSERVER_PORT" "value" "3000") -}}
{{- else if eq .name "websocket" -}}
{{- $env = list (dict "name" "ZAMMAD_WEBSOCKET_PORT" "value" "6042") -}}
{{- else if eq .name "scheduler" -}}
{{- $env = list (dict "name" "POSTGRESQL_DB_CREATE" "value" "false") -}}
{{- end -}}
{{- $env | toYaml -}}
{{- end -}}

{{/* Component environment: the chart defaults, then the shared env, then components.<name>.env; a later entry replaces an earlier one of the same name. Never renders duplicates. */}}
{{- define "zammad.env" -}}
{{- $items := dict -}}
{{- $order := list -}}
{{- range (include "zammad.defaultEnv" . | fromYamlArray) -}}
{{- if not (hasKey $items .name) }}{{ $order = append $order .name }}{{ end -}}
{{- $_ := set $items .name . -}}
{{- end -}}
{{- range .root.Values.env -}}
{{- if not (hasKey $items .name) }}{{ $order = append $order .name }}{{ end -}}
{{- $_ := set $items .name . -}}
{{- end -}}
{{- range .component.env -}}
{{- if not (hasKey $items .name) }}{{ $order = append $order .name }}{{ end -}}
{{- $_ := set $items .name . -}}
{{- end -}}
{{- range $key := $order }}
- {{ toYaml (get $items $key) | nindent 2 | trim }}
{{- end -}}
{{- end -}}

{{/* A component's deployment value, or the shared value when the component sets none. */}}
{{- define "zammad.componentValue" -}}
{{- /* Helm versions differ: an unset (null) value is either nil or removed from the map. */ -}}
{{- $value := index .component .key -}}
{{- if or (kindIs "invalid" $value) (eq (toString $value) "") -}}{{- $value = index .root.Values .key -}}{{- end -}}
{{- $value -}}
{{- end -}}
