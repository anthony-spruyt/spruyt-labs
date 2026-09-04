{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeSchedulerConfig
config:
  profiles:
    - schedulerName: default-scheduler
      plugins:
        score:
          disabled:
            - name: ImageLocality
{{- else }}
cluster:
  scheduler:
    config:
      apiVersion: kubescheduler.config.k8s.io/v1
      kind: KubeSchedulerConfiguration
      profiles:
        - schedulerName: default-scheduler
          plugins:
            score:
              disabled:
                - name: ImageLocality
{{- end }}
