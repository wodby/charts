{{/*
Return the proper wsp-client image name
*/}}
{{- define "wsp-client.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Create the name of the deployment
*/}}
{{- define "wsp-client.fullname" -}}
    {{ printf "%s" (include "common.names.fullname" .) }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "wsp-client.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "wsp-client.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "wsp-client.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Name the configuration configmap
*/}}
{{- define "wsp-client.configuration.configMap" -}}
{{- printf "%s-config" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
