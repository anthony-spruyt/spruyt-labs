# MCXboxBroadcast - Friends-tab Listing for Chicken

## Overview

Lets friends of a dedicated Microsoft account join the household's Bedrock server (Chicken) from the in-game **Friends** tab, so a remote console player needs no DNS changes. The bot signs in to Xbox Live as that account and advertises a session to its friends. It relays each joining client's NetherNet offer to Chicken's HTTP signaling and returns Chicken's answer. The client then connects to
Chicken over UDP directly, so the bot has no Service and accepts no inbound traffic. The session details it advertises (name, player count) are queried from Chicken, falling back to the names in `app/values.yaml`.

## Prerequisites

- A Microsoft account reserved for the bot, with a gamertag. Sign-in is interactive (see below), so no credentials are stored in Git.
- Chicken reachable from the internet as described in [Crafty Controller, Remote play](../crafty-controller/README.md#remote-play). The bot only brokers the handshake; if the UDP forwards or the advertised address are wrong, the client sees the listing but cannot connect.

## Operations

### First sign-in

On an empty PVC the pod logs a `microsoft.com/link` URL and a one-time code:

```bash
kubectl logs -n minecraft deploy/mcxboxbroadcast | grep -i "sign in"
```

Open the URL while signed in as the bot account and enter the code. If it expires first, restart the Deployment for a fresh one. The sign-in tokens and player history live in `cache/` on the `mcxboxbroadcast-config` PVC (labelled for Velero backup), so restarts do not ask again; deleting the PVC means signing in again.

### Joining

Each player adds the bot's gamertag as a friend in Minecraft. The bot accepts the request, sends an invite, and Chicken then appears under the **Friends** tab. By default the bot unfriends players who have not joined for a while (`friend-sync.expiry` upstream), so a long-absent player adds it again. Chicken's allow-list is on, so also add each player there in Crafty; the bot only brokers the
connection.

### Configuration

The init container copies `config.yml` from the `mcxboxbroadcast` ConfigMap over the PVC copy on every start, because the app rewrites that file when it migrates the config version. Change settings in `app/values.yaml`, not on the PVC. Keep `config-version` equal to the `CONFIG_VERSION` the pinned image expects.

The image only publishes `latest`, so `values.yaml` pins `latest@sha256:<digest>` and Renovate bumps the digest.

## References

- [MCXboxBroadcast](https://github.com/MCXboxBroadcast/Broadcaster)
