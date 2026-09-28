# mosquitto - MQTT Broker

## Overview

LAN MQTT broker on the `${MOSQUITTO_IP4}` LoadBalancer address, for home-automation devices and in-cluster publishers such as `sungather`. Plain MQTT on 1883 and TLS on 8883 (cert for `mosquitto.lan.${EXTERNAL_DOMAIN}`).

## Operations

### Users

Anonymous access is off on both listeners. Users live in the `credentials.txt` key of `app/mosquitto-secrets.sops.yaml` as a mosquitto password file (hashed entries generated with `mosquitto_passwd`). The `copy-secrets` init container copies it into an `emptyDir` owned by the mosquitto user with `0700` permissions; mosquitto 2.x checks the owner and mode of its password file, which a Secret mount
cannot satisfy.

To add or rotate a user: generate the hashed line locally with `mosquitto_passwd`, edit the SOPS file with `sops`, and push. Reloader restarts the broker.

### Adding an in-cluster client

Add an egress CNP in the client's namespace to `mosquitto` pods on 1883/8883 (see `sungather/app/network-policies.yaml`) and an ingress rule in `app/network-policies.yaml` here.
