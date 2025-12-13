{{/*
Expand the name of the chart.
*/}}
{{- define "tis-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 |
{{- /*
   TRUNCATION:
   Kubernetes resource names are limited to 63 characters (DNS Label Standard).
   We strictly enforce this to prevent deployment failures with long release names.
*/ -}}
trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "tis-stack.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 |
trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- /*
   LOGIC:
   If the Release Name (e.g., 'tis-stack') already contains the Chart Name,
   we avoid duplication (e.g., 'tis-stack-tis-stack') by using just the Release Name.
*/ -}}
{{- .Release.Name |
trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 |
trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tis-stack.chart" -}}
{{- /*
   SANITIZATION:
   Replaces '+' with '_' because semantic versioning allows '+',
   but Kubernetes labels do not allow it.
*/ -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 |
trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "tis-stack.labels" -}}
helm.sh/chart: {{ include "tis-stack.chart" . }}
{{ include "tis-stack.selectorLabels" .
}}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- /*
   AUDIT:
   Tracks which tool manages this resource. Useful when multiple controllers
   (e.g., Helm, Terraform, kubectl) coexist in the same cluster.
*/ -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "tis-stack.selectorLabels" -}}
{{- /*
   PURPOSE:
   These labels are immutable for Deployments/StatefulSets.
   They form the glue between Services and Pods.
*/ -}}
app.kubernetes.io/name: {{ include "tis-stack.name" .
}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
