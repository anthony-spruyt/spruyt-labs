# topf sets machine.install.image itself; the annotation mirrors it so that
# `kubectl get node -o jsonpath` can report the installer without talking to the
# Talos API. Factory, platform and the secureboot suffix are fixed here because
# topf.yaml pins all three cluster-wide. The version falls back the same way topf's
# own InstallerImage() does, so a per-node talosVersion during a staged upgrade does
# not leave the annotation pointing at the cluster-wide release.
machine:
  install:
    grubUseUKICmdline: true
  nodeAnnotations:
    installerImage: factory.talos.dev/metal-installer-secureboot/{{ .SchematicID }}:v{{ trimPrefix "v" (default .TalosVersion .Node.TalosVersion) }}
