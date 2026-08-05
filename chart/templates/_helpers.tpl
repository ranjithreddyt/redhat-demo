{{- define "nginx-app.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{- define "nginx-app.labels" -}}
app.kubernetes.io/name: {{ include "nginx-app.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
