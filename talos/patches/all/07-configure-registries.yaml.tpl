---
apiVersion: v1alpha1
kind: RegistryAuthConfig
name: ghcr.io
username: {{ .Data.ghUsername }}
password: {{ .Data.ghToken }}
---
apiVersion: v1alpha1
kind: RegistryAuthConfig
name: registry-1.docker.io
username: {{ .Data.dockerUsername }}
password: {{ .Data.dockerToken }}
