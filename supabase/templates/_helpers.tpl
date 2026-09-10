{{/* Stable resource names reserve suffix space for component identities. */}}
{{- define "supabase.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 40 | trimSuffix "-" -}}
{{- end -}}
{{- define "supabase.componentName" -}}
{{- if eq .name "gateway" -}}{{ include "supabase.fullname" .root }}{{- else -}}{{ include "supabase.fullname" .root }}-{{ .name }}{{- end -}}
{{- end -}}
{{- define "supabase.name" -}}{{ default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}{{- end -}}
{{- define "supabase.labels" -}}
app.kubernetes.io/name: {{ include "supabase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
{{- define "supabase.serviceAccount" -}}
{{- if .Values.serviceAccount.create -}}{{ default (include "supabase.fullname" .) .Values.serviceAccount.name }}{{- else -}}{{ default "default" .Values.serviceAccount.name }}{{- end -}}
{{- end -}}
{{- define "supabase.sourceHash" -}}
{{- printf "%s:%s" (.Values.credentials | toJson) (.Files.Get "files/bootstrap.cjs") | sha256sum -}}
{{- end -}}
{{- define "supabase.image" -}}
{{ printf "%s:%s" .repository .tag }}
{{- end -}}
{{/* User-supplied env values replace defaults by name; never render duplicate keys. */}}
{{- define "supabase.env" -}}
{{- $items := dict -}}
{{- range .defaults -}}{{- $_ := set $items .name . -}}{{- end -}}
{{- range .extra -}}{{- $_ := set $items .name . -}}{{- end -}}
{{- range $key := keys $items | sortAlpha }}
- {{ toYaml (get $items $key) | nindent 2 | trim }}
{{- end -}}
{{- end -}}
{{/* Wodby integrations enter through the primary container mapping; dispatch only recognized variables to their consumer. */}}
{{- define "supabase.componentEnv" -}}
{{- $smtp := dict "RELAY_HOST" "GOTRUE_SMTP_HOST" "RELAY_PORT" "GOTRUE_SMTP_PORT" "RELAY_USER" "GOTRUE_SMTP_USER" "RELAY_PASSWORD" "GOTRUE_SMTP_PASS" -}}
{{- $storage := list "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN" "REGION" "STORAGE_BACKEND" "GLOBAL_S3_BUCKET" "GLOBAL_S3_ENDPOINT" "GLOBAL_S3_FORCE_PATH_STYLE" -}}
{{- $result := list -}}
{{- range .root.Values.integrationEnv -}}
{{- $entry := deepCopy . -}}
{{- if and (eq $.name "auth") (hasKey $smtp .name) -}}
{{- $_ := set $entry "name" (get $smtp .name) -}}{{- $result = append $result $entry -}}
{{- else if and (eq $.name "storage") (has .name $storage) -}}
{{- $result = append $result $entry -}}
{{- else if and (eq $.name "gateway") (not (hasPrefix "RELAY_" .name)) (not (has .name $storage)) -}}
{{- $result = append $result $entry -}}
{{- end -}}
{{- end -}}
{{- $result | toYaml -}}
{{- end -}}
