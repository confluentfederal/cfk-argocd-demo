{{/*
Common labels
*/}}
{{- define "syslog-reconstruction.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: confluent-platform
{{- end }}

{{/*
Selector labels
*/}}
{{- define "syslog-reconstruction.selectorLabels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
