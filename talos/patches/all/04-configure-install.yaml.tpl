# topf sets machine.install.image itself; the annotation mirrors it so that
# `kubectl get node -o jsonpath` can report the installer without talking to the
# Talos API. Factory, platform and the secureboot suffix are fixed here because
# topf.yaml pins all three cluster-wide. The version falls back the same way topf's
# own InstallerImage() does, so a per-node talosVersion during a staged upgrade does
# not leave the annotation pointing at the cluster-wide release.
{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeNodeConfig
annotations:
  installerImage: factory.talos.dev/metal-installer-secureboot/{{ .SchematicID }}:v{{ trimPrefix "v" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
{{- else }}
machine:
  nodeAnnotations:
    installerImage: factory.talos.dev/metal-installer-secureboot/{{ .SchematicID }}:v{{ trimPrefix "v" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
{{- end }}
{{- if not (semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion)) }}
---
machine:
  install:
    # GRUB-only knob, and these nodes boot systemd-boot from a UKI because topf.yaml
    # sets secureboot. UnattendedInstallConfig has no equivalent and needs none.
    grubUseUKICmdline: true
{{- end }}
