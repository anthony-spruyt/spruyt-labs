{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeControllerManagerConfig
extraArgs:
  terminated-pod-gc-threshold: "50"
{{- else }}
cluster:
  controllerManager:
    extraArgs:
      terminated-pod-gc-threshold: "50"
{{- end }}
