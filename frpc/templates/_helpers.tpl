{{/*
Return the proper frpc image name
*/}}
{{- define "frpc.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Create the name of the deployment
*/}}
{{- define "frpc.fullname" -}}
    {{ printf "%s" (include "common.names.fullname" .) }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "frpc.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "frpc.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "frpc.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Name the configuration configmap
*/}}
{{- define "frpc.configuration.configMap" -}}
{{- printf "%s-config" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the secret that stores frpc credentials
*/}}
{{- define "frpc.secretName" -}}
{{- if .Values.frpc.existingSecret -}}
{{- .Values.frpc.existingSecret -}}
{{- else -}}
{{- printf "%s-secret" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
