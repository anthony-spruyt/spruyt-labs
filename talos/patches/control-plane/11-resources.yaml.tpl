{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeAPIServerConfig
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    memory: 4Gi
---
apiVersion: v1alpha1
kind: KubeControllerManagerConfig
resources:
  requests:
    cpu: 300m
    memory: 512Mi
  limits:
    memory: 1Gi
---
apiVersion: v1alpha1
kind: KubeSchedulerConfig
resources:
  requests:
    cpu: 50m
    memory: 512Mi
  limits:
    memory: 1Gi
{{- else }}
cluster:
  apiServer:
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi
      limits:
        memory: 4Gi
  controllerManager:
    resources:
      requests:
        cpu: 300m
        memory: 512Mi
      limits:
        memory: 1Gi
  scheduler:
    resources:
      requests:
        cpu: 50m
        memory: 512Mi
      limits:
        memory: 1Gi
{{- end }}
