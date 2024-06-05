{{/*
Copyright VMware, Inc.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/* vim: set filetype=mustache: */}}
{{/*
Return the proper VARNISH image name
*/}}
{{- define "varnish.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper GIT image name
*/}}
{{- define "varnish.cloneStaticSiteFromGit.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.cloneStaticSiteFromGit.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Prometheus metrics image name
*/}}
{{- define "varnish.metrics.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.metrics.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "varnish.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image .Values.cloneStaticSiteFromGit.image .Values.metrics.image) "context" $) }}
{{- end -}}

{{/*
Return true if a static site should be mounted in the VARNISH container
*/}}
{{- define "varnish.useStaticSite" -}}
{{- if or .Values.cloneStaticSiteFromGit.enabled .Values.staticSiteConfigmap .Values.staticSitePVC }}
    {- true -}}
{{- end -}}
{{- end -}}

{{/*
Return the volume to use to mount the static site in the VARNISH container
*/}}
{{- define "varnish.staticSiteVolume" -}}
{{- if .Values.cloneStaticSiteFromGit.enabled }}
emptyDir: {}
{{- else if .Values.staticSiteConfigmap }}
configMap:
  name: {{ printf "%s" (tpl .Values.staticSiteConfigmap $) -}}
{{- else if .Values.staticSitePVC }}
persistentVolumeClaim:
  claimName: {{ printf "%s" (tpl .Values.staticSitePVC $) -}}
{{- end }}
{{- end -}}

{{/*
Return the custom VARNISH server block configmap.
*/}}
{{- define "varnish.serverBlockConfigmapName" -}}
{{- if .Values.existingServerBlockConfigmap -}}
    {{- printf "%s" (tpl .Values.existingServerBlockConfigmap $) -}}
{{- else -}}
    {{- printf "%s-server-block" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Compile all warnings into a single message, and call fail.
*/}}
{{- define "varnish.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "varnish.validateValues.cloneStaticSiteFromGit" .) -}}
{{- $messages := append $messages (include "varnish.validateValues.extraVolumes" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}

{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{/* Validate values of VARNISH - Clone StaticSite from Git configuration */}}
{{- define "varnish.validateValues.cloneStaticSiteFromGit" -}}
{{- if and .Values.cloneStaticSiteFromGit.enabled (or (not .Values.cloneStaticSiteFromGit.repository) (not .Values.cloneStaticSiteFromGit.branch)) -}}
varnish: cloneStaticSiteFromGit
    When enabling cloing a static site from a Git repository, both the Git repository and the Git branch must be provided.
    Please provide them by setting the `cloneStaticSiteFromGit.repository` and `cloneStaticSiteFromGit.branch` parameters.
{{- end -}}
{{- end -}}

{{/* Validate values of VARNISH - Incorrect extra volume settings */}}
{{- define "varnish.validateValues.extraVolumes" -}}
{{- if and (.Values.extraVolumes) (not (or .Values.extraVolumeMounts .Values.cloneStaticSiteFromGit.extraVolumeMounts)) -}}
varnish: missing-extra-volume-mounts
    You specified extra volumes but not mount points for them. Please set
    the extraVolumeMounts value
{{- end -}}
{{- end -}}

{{/*
 Create the name of the service account to use
 */}}
{{- define "varnish.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}
