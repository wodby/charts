{{/*
Return the proper gotenberg image name
*/}}
{{- define "gotenberg.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Create the name of the deployment
*/}}
{{- define "gotenberg.fullname" -}}
    {{ printf "%s" (include "common.names.fullname" .) }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "gotenberg.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "gotenberg.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "gotenberg.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Name the configuration configmap
*/}}
{{- define "gotenberg.configuration.configMap" -}}
{{- printf "%s-config" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
