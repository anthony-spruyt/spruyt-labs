apiVersion: v1alpha1
kind: ResolverConfig
nameservers:
{{- range .Data.nameservers }}
  - address: {{ . }}
{{- end }}
searchDomains:
  disableDefault: true
