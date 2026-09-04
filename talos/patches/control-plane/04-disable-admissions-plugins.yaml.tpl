{{- /*
Disable default API server admission plugins so that they do not conflict with
mutating admission policy. v1.14 emits one KubeAdmissionControlConfig document per
plugin, so the empty list becomes a delete of the document Talos generates.
*/ -}}
{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeAdmissionControlConfig
name: PodSecurity
$patch: delete
{{- else }}
cluster:
  apiServer:
    admissionControl: []
{{- end }}
