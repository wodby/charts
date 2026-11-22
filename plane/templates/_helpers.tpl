{{/* Chart name, used for the app.kubernetes.io/name label. */}}
{{- define "plane.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Base resource name. It leaves room for the longest component suffix (-scheduler). */}}
{{- define "plane.fullname" -}}
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

{{/* Resource name of a component. The proxy takes the base name, because it serves the app. */}}
{{- define "plane.componentName" -}}
{{- if eq .name "proxy" -}}
{{ include "plane.fullname" .root }}
{{- else -}}
{{ include "plane.fullname" .root }}-{{ .name }}
{{- end -}}
{{- end -}}

{{/* Fully qualified address of a component's Service. */}}
{{- define "plane.serviceAddress" -}}
{{ include "plane.componentName" . }}.{{ .root.Release.Namespace }}.svc.{{ .root.Values.clusterDomain }}:{{ .port }}
{{- end -}}

{{- define "plane.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "plane.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "plane.labels" -}}
helm.sh/chart: {{ include "plane.chart" . }}
{{ include "plane.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "plane.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "plane.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/* A component's image: its own repository, with the shared registry, tag, digest and pull policy unless it sets its own. */}}
{{- define "plane.imageRoot" -}}
{{- $shared := .root.Values.image -}}
{{- $own := .component.image | default dict -}}
{{- dict
  "registry" (default $shared.registry $own.registry)
  "repository" $own.repository
  "tag" (default $shared.tag $own.tag)
  "digest" (default $shared.digest $own.digest)
  "pullPolicy" (default $shared.pullPolicy $own.pullPolicy)
  | toYaml -}}
{{- end -}}

{{- define "plane.image" -}}
{{- $imageRoot := include "plane.imageRoot" . | fromYaml -}}
{{ include "common.images.image" (dict "imageRoot" $imageRoot "global" .root.Values.global "chart" .root.Chart) }}
{{- end -}}

{{- define "plane.imagePullPolicy" -}}
{{- (include "plane.imageRoot" . | fromYaml).pullPolicy -}}
{{- end -}}

{{- define "plane.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) }}
{{- end -}}

{{/* Environment defaults of a component. */}}
{{- define "plane.defaultEnv" -}}
{{- $root := .root -}}
{{- $env := list -}}
{{- if eq .name "proxy" -}}
{{- $env = list
  (dict "name" "PROXY_PORT" "value" "8080")
  (dict "name" "PLANE_WEB_UPSTREAM" "value" (include "plane.serviceAddress" (dict "root" $root "name" "web" "port" 3000)))
  (dict "name" "PLANE_ADMIN_UPSTREAM" "value" (include "plane.serviceAddress" (dict "root" $root "name" "admin" "port" 3000)))
  (dict "name" "PLANE_SPACE_UPSTREAM" "value" (include "plane.serviceAddress" (dict "root" $root "name" "space" "port" 3000)))
  (dict "name" "PLANE_LIVE_UPSTREAM" "value" (include "plane.serviceAddress" (dict "root" $root "name" "live" "port" 3000)))
  (dict "name" "PLANE_API_UPSTREAM" "value" (include "plane.serviceAddress" (dict "root" $root "name" "api" "port" 8000)))
-}}
{{- else if eq .name "live" -}}
{{- $env = list
  (dict "name" "API_BASE_URL" "value" (printf "http://%s" (include "plane.serviceAddress" (dict "root" $root "name" "api" "port" 8000))))
  (dict "name" "LIVE_BASE_PATH" "value" "/live")
  (dict "name" "PORT" "value" "3000")
-}}
{{- else if eq .name "api" -}}
{{- $env = list (dict "name" "PORT" "value" "8000") -}}
{{- end -}}
{{- $env | toYaml -}}
{{- end -}}

{{/* Component environment: the chart defaults, then the shared env, then components.<name>.env; a later entry replaces an earlier one of the same name. Never renders duplicates. */}}
{{- define "plane.env" -}}
{{- $items := dict -}}
{{- $order := list -}}
{{- range (include "plane.defaultEnv" . | fromYamlArray) -}}
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
{{- define "plane.componentValue" -}}
{{- /* Helm versions differ: an unset (null) value is either nil or removed from the map. */ -}}
{{- $value := index .component .key -}}
{{- if or (kindIs "invalid" $value) (eq (toString $value) "") -}}{{- $value = index .root.Values .key -}}{{- end -}}
{{- $value -}}
{{- end -}}
