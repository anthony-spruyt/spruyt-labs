{{- /*
USB access for the NUT server talking to the CyberPower CP1500.
Label and udev rules move together if the UPS is relocated to another node.
*/ -}}
{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  ups.spruyt-labs.io/connected: "true"
{{- else }}
machine:
  nodeLabels:
    ups.spruyt-labs.io/connected: "true"
{{- end }}
---
machine:
  udev:
    rules:
      - SUBSYSTEM=="usb", ATTR{idVendor}=="0764", MODE="0666"
      - KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666"
      - KERNEL=="hiddev*", SUBSYSTEM=="usbmisc", MODE="0666"
