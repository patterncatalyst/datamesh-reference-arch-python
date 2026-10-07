{{/*
Common labels applied to every object, following the k8s recommended label set
the charts/capstone subcharts already use (app.kubernetes.io/part-of: capstone).
*/}}
{{- define "datamesh.labels" -}}
app.kubernetes.io/part-of: capstone
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
In-cluster DNS suffix for the release namespace, e.g. datamesh.svc.cluster.local.
Used to build the cross-service URLs in the app ConfigMap and Kafka's listeners,
so the chart works unchanged in whatever namespace it is installed into.
*/}}
{{- define "datamesh.dns" -}}
{{ .Release.Namespace }}.svc.cluster.local
{{- end -}}
