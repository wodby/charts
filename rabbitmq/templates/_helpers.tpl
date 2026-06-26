{{/*
Return the proper RabbitMQ image name.
*/}}
{{- define "rabbitmq.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker image pull secrets.
*/}}
{{- define "rabbitmq.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) }}
{{- end -}}

{{/*
Create the name of the service account to use.
*/}}
{{- define "rabbitmq.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "common.names.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Return the headless service name.
*/}}
{{- define "rabbitmq.headlessServiceName" -}}
{{- printf "%s-headless" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Return the generated secret name.
*/}}
{{- define "rabbitmq.generatedSecretName" -}}
{{ include "common.names.fullname" . }}
{{- end -}}

{{/*
Return the password secret name.
*/}}
{{- define "rabbitmq.passwordSecretName" -}}
{{- if .Values.auth.existingPasswordSecret -}}
{{- tpl .Values.auth.existingPasswordSecret $ -}}
{{- else -}}
{{- include "rabbitmq.generatedSecretName" . -}}
{{- end -}}
{{- end -}}

{{/*
Return the password secret key.
*/}}
{{- define "rabbitmq.passwordSecretKey" -}}
{{- default "password" .Values.auth.existingPasswordSecretKey -}}
{{- end -}}

{{/*
Return the Erlang cookie secret name.
*/}}
{{- define "rabbitmq.erlangSecretName" -}}
{{- if .Values.auth.existingErlangSecret -}}
{{- tpl .Values.auth.existingErlangSecret $ -}}
{{- else -}}
{{- include "rabbitmq.generatedSecretName" . -}}
{{- end -}}
{{- end -}}

{{/*
Return the Erlang cookie secret key.
*/}}
{{- define "rabbitmq.erlangSecretKey" -}}
{{- default "erlang-cookie" .Values.auth.existingErlangSecretKey -}}
{{- end -}}

{{/*
Return true if the chart must generate credentials.
*/}}
{{- define "rabbitmq.createGeneratedSecret" -}}
{{- if or (not .Values.auth.existingPasswordSecret) (not .Values.auth.existingErlangSecret) -}}
true
{{- end -}}
{{- end -}}

{{/*
Return the plugin list for the Wodby image.
*/}}
{{- define "rabbitmq.plugins" -}}
{{- $plugins := list -}}
{{- if .Values.management.enabled -}}
{{- $plugins = append $plugins "rabbitmq_management" -}}
{{- end -}}
{{- if .Values.metrics.enabled -}}
{{- $plugins = append $plugins "rabbitmq_prometheus" -}}
{{- end -}}
{{- if gt (int .Values.replicaCount) 1 -}}
{{- $plugins = append $plugins "rabbitmq_peer_discovery_k8s" -}}
{{- end -}}
{{- range .Values.extraPlugins -}}
{{- $plugins = append $plugins . -}}
{{- end -}}
{{ join "," ($plugins | uniq) }}
{{- end -}}
