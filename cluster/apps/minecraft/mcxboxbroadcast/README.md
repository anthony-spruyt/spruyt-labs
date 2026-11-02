# MCXboxBroadcast - Friends-tab Listing for Chicken

## Overview

Lists Chicken, the household's Bedrock server, under the in-game **Friends** tab of a dedicated Microsoft account, so a remote console player needs no DNS changes. The bot only brokers the handshake: it has no Service and accepts no inbound traffic.

## Prerequisites

- A Microsoft account reserved for the bot, with an Xbox profile: sign in once at xbox.com to create the gamertag. Sign-in is interactive (see below), so no credentials are stored in Git.
- At the device-code step the account must sign in with username and password, not a passwordless method. If it has no password, add one under account.microsoft.com Security first. Upstream logs "Sign in with username and password, not a passwordless method" on repeated `invalid_grant`.
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

### Join relay

The bot advertises a session to its friends. When one joins, it relays the client's NetherNet offer to Chicken's HTTP signaling on `session.remote-port` and returns Chicken's answer; the client then connects to Chicken over UDP directly. Moving Chicken's signaling port means updating `remote-port` and the `allow-crafty-mcxboxbroadcast-ingress` and `allow-mcxboxbroadcast-crafty-egress` policies.

### Configuration

While Chicken answers, the session's host and world names come from Chicken itself (its `server-name` and `level-name`). The `session-info` names in `app/values.yaml` show only when Chicken doesn't answer. Don't rename Chicken's `level-name`, because it names the world folder.

The init container copies `config.yml` from the `mcxboxbroadcast` ConfigMap over the PVC copy on every start, because the app rewrites that file when it migrates the config version. Change settings in `app/values.yaml`, not on the PVC. Keep `config-version` equal to the `CONFIG_VERSION` the pinned image expects.

The image only publishes `latest`, so `values.yaml` pins `latest@sha256:<digest>` and Renovate bumps the digest.

## References

- [MCXboxBroadcast](https://github.com/MCXboxBroadcast/Broadcaster)
