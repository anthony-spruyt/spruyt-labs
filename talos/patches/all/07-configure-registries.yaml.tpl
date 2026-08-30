machine:
  registries:
    config:
      ghcr.io:
        auth:
          username: {{ .Data.ghUsername }}
          password: {{ .Data.ghToken }}
      registry-1.docker.io:
        auth:
          username: {{ .Data.dockerUsername }}
          password: {{ .Data.dockerToken }}
