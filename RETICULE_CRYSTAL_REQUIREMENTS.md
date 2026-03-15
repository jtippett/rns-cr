# Reticule: Crystal Daemon Requirements

## Overview

The Crystal RNS daemon serves dual roles: it is the local RNS transport for applications on the host machine (replacing Python `rnsd`), and it is the management agent for Reticule (the centralized Elixir management service). This document specifies the extensions needed to the existing Crystal RNS port to support Reticule integration.

## Design Philosophy

Reticule aims to make RNS network creation and management as simple as Tailscale. The admin thinks in terms of **nodes** (my devices), **segments** (my virtual networks), and the **network map** (who can reach what). They never see INI files, IFAC key derivation math, or announce rate formulas. All intelligence lives in Reticule (Elixir). The Crystal daemon is a thin, reliable agent that reports state and applies instructions.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Host Machine                                       │
│                                                     │
│  ┌──────────┐  ┌──────────┐  LocalInterface (IPC)   │
│  │ LXMF App │  │ Custom   │◄────────────┐          │
│  └────┬─────┘  │ RNS App  │             │          │
│       │        └────┬─────┘             │          │
│       └──────┐      │          ┌────────┴────────┐ │
│              ▼      ▼          │  Crystal Daemon  │ │
│         SharedInstance(37428)──►│                  │ │
│                                │  ┌────────────┐  │ │
│                                │  │ Management │  │ │
│                                │  │ Module     │──┼─┼──► Reticule (Elixir)
│                                │  └────────────┘  │ │    via RNS Link
│                                │                  │ │
│                                │  ┌────────────┐  │ │
│                                │  │ Data Plane │  │ │
│                                │  │ Interfaces │──┼─┼──► Network Peers
│                                │  └────────────┘  │ │
│                                └──────────────────┘ │
└─────────────────────────────────────────────────────┘
```

The daemon runs two logical channels:

1. **User channel** — the standard shared instance LocalInterface on port 37428. Local applications connect here. Unchanged from current behavior.
2. **Management channel** — an RNS Link to Reticule's management Destination, carried over a dedicated bootstrap interface (typically TCP to a known Reticule endpoint). Used exclusively for control plane traffic.

---

## IFAC Model

IFAC (Interface Authentication Code) is **per-interface, not per-network**. Key properties:

- Each interface independently derives its own IFAC signing identity from its `network_name` and/or `passphrase`
- Different interfaces on the same node can have different IFAC credentials (or none)
- IFAC is validated and stripped on ingress, then recalculated fresh on egress per the outbound interface's credentials
- A Transport node with credentials for multiple IFAC-protected interfaces bridges between those virtual segments
- Packets crossing from an IFAC interface to a non-IFAC interface have IFAC stripped; packets going the other direction get IFAC added
- IFAC creates virtual network isolation at each interface boundary — not end-to-end

**Reticule manages IFAC through ConfigPush.** "Segments" are a Reticule UI concept: a named set of IFAC credentials applied to specific interfaces on specific nodes. The Crystal daemon does not need a segment concept — it receives concrete instructions ("set these IFAC credentials on this interface") via ConfigPush.

---

## 1. Management Module (`src/rns/management/`)

New module added to the Crystal daemon. Responsible for all Reticule communication.

### 1.1 Management Destination

- Register a Destination with aspect path `reticule.node.mgmt` (direction: IN) on startup, allowing Reticule to establish inbound links. For outbound links to Reticule, an OUT destination is created dynamically during link establishment.
- The Destination's Identity is the node's own Identity (generated on first run, persisted)
- Reticule's management Destination hash is provided via bootstrap config (see §2)

### 1.2 Management Link

- On startup (after interfaces are initialized), establish an RNS Link to Reticule's management Destination
- The Link provides encrypted, authenticated bidirectional communication
- Implement reconnection logic: if the Link tears down, re-establish with exponential backoff (initial 5s, max 300s)
- Expose link status: `connected`, `connecting`, `disconnected` with timestamp of last state change
- The management Link is established over a **dedicated bootstrap interface** (see §2) that is never modified by config pushes — this prevents management lockout

### 1.3 Management Protocol Messages

All messages are RNS Channel MessageBase subclasses with MessagePack serialization. Each has a unique `MSGTYPE` (range 0x0100–0x01FF reserved for management).

Six message types for v1. The daemon is deliberately thin — all intelligence lives in Reticule.

#### 1.3.1 NodeStateReport (node → Reticule)

Sent periodically (default: every 30 seconds) and on significant state changes. This is the primary input for Reticule's topology engine and network map.

```
MSGTYPE: 0x0100

Fields:
  node_identity_hash : Bytes[16]     # this node's truncated identity hash
  uptime             : Float64        # seconds since daemon start
  config_hash        : Bytes[32]      # SHA-256 of current config file contents
  timestamp          : Float64        # current time

  interfaces: Array of:
    name             : String
    type             : String         # class name (e.g. "AutoInterface")
    mode             : UInt8          # MODE_FULL, MODE_GATEWAY, etc.
    online           : Bool
    bitrate          : Int64
    mtu              : UInt16
    rxb              : UInt64         # total bytes received
    txb              : UInt64         # total bytes transmitted
    peers            : Array[Bytes[16]]  # connected peer identity hashes (for TCP/Auto)
    ifac_configured  : Bool
    ifac_netname     : String?        # network_name if set (NOT the passphrase — never send credentials upstream)
    announce_queue_size : UInt32

  announce_table: Array of:
    dest_hash        : Bytes[16]
    hops             : UInt8
    interface_name   : String         # receiving interface
    timestamp        : Float64
    expires          : Float64

  path_table: Array of:
    dest_hash        : Bytes[16]
    next_hop         : Bytes[16]
    hops             : UInt8
    interface_name   : String
    expires          : Float64

  active_links: Array of:
    dest_hash        : Bytes[16]
    status           : UInt8          # PENDING, ACTIVE, STALE, etc.
    rtt              : Float64?       # measured RTT in seconds
    established_at   : Float64?
```

#### 1.3.2 ConfigPush (Reticule → node)

Delivers a complete or partial configuration update. This is the single mechanism for all config changes — interface parameters, IFAC credentials, announce rates, transport mode, everything. Reticule computes what needs to change; the daemon applies it.

```
MSGTYPE: 0x0101

Fields:
  push_id            : Bytes[16]      # unique ID for this push (for ack correlation)
  strategy           : UInt8          # 0 = full replace, 1 = section merge
  config_sections    : Map[String, Map[String, String]]  # section → key → value
  expected_hash      : Bytes[32]      # SHA-256 of expected config after application
```

Reticule does not send `restart_hint` — the daemon determines what kind of reload is needed by diffing the incoming config against running state (see §3).

#### 1.3.3 ConfigAck (node → Reticule)

Acknowledges a ConfigPush.

```
MSGTYPE: 0x0102

Fields:
  push_id            : Bytes[16]      # correlates to ConfigPush.push_id
  status             : UInt8          # 0 = applied, 1 = applied_pending_restart,
                                      # 2 = validation_failed, 3 = apply_failed
  config_hash        : Bytes[32]      # SHA-256 of actual config after application
  error_message      : String?        # human-readable error if status > 1
```

#### 1.3.4 Heartbeat (bidirectional)

Lightweight keepalive for the management channel. Supplements RNS Link keepalive with application-level liveness.

```
MSGTYPE: 0x0103

Fields:
  timestamp          : Float64
  sequence           : UInt32
```

#### 1.3.5 JoinRequest (node → Reticule)

Sent once during bootstrap to register this node with Reticule.

```
MSGTYPE: 0x0110

Fields:
  token_secret       : Bytes[32]      # one-time auth from provisioning token
  identity_pubkey    : Bytes[64]      # X25519 + Ed25519 public keys
  hostname           : String
  platform           : String         # e.g. "linux-x86_64"
  daemon_version     : String
```

#### 1.3.6 JoinResponse (Reticule → node)

```
MSGTYPE: 0x0111

Fields:
  accepted           : Bool
  node_id            : Bytes[16]?     # Reticule's internal ID (if accepted)
  config_sections    : Map[String, Map[String, String]]?  # full config (if accepted)
  reject_reason      : String?        # "token_expired", "token_invalid", etc. (if rejected)
```

---

## 2. Bootstrap and Auto-Join

### 2.1 Provisioning Token

A provisioning token encodes the minimum information needed for a new node to find and authenticate with Reticule. Generated by Reticule's admin UI.

```
Token contents (MessagePack, then base32-encoded for human handling):
  reticule_dest_hash : Bytes[16]      # Reticule management Destination hash
  bootstrap_interface: Map             # minimal interface config to reach Reticule
    type             : String          # typically "TCPClientInterface" or "BackboneClientInterface"
    target_host      : String
    target_port      : UInt16
    network_name     : String?         # IFAC for the bootstrap link (if needed)
    passphrase       : String?
  token_secret       : Bytes[32]       # one-time auth token
  token_expires      : Float64         # expiry timestamp
```

### 2.2 Onboarding Flow

The user experience:

```
$ crns --join reti://reticule.example.com/join/a8f3e2...
Connecting to Reticule... done
Registered as "james-workstation"
Joined segment "office" on AutoInterface
3 peers visible
```

Under the hood:

1. Admin generates provisioning token in Reticule UI
2. Token is provided to the new node (CLI flag, URL, QR code, or file)
3. Crystal daemon parses token, starts with minimal config:
   - Shared instance LocalInterface (for local apps)
   - Bootstrap interface decoded from token
4. Daemon discovers Reticule's Destination (direct path via bootstrap TCP endpoint)
5. Daemon establishes management Link to Reticule
6. Daemon sends `JoinRequest` with token_secret and its identity
7. Reticule validates token, registers node, responds with `JoinResponse`:
   - Full configuration for this node (all interfaces, IFAC, modes, rates)
8. Daemon writes full config, applies it via hot reload engine (§3)
9. Node begins normal operation: periodic `NodeStateReport`, accepts `ConfigPush`
10. Node appears on Reticule's network map in real time

### 2.3 Bootstrap Interface Protection

The bootstrap interface (decoded from the provisioning token) is marked `management_protected = true` internally:

- ConfigPush will never modify or remove this interface
- It ensures the management channel always has a path to Reticule
- If a bad config push breaks all data-plane interfaces, management access survives
- The bootstrap interface carries management traffic; it also participates in data-plane routing unless explicitly configured otherwise

### 2.4 Post-Join Persistence

After successful join:

- The full config (including bootstrap interface and management section) is written to the standard config path (`~/.reticulum/config`)
- The provisioning token is discarded (not persisted)
- Subsequent daemon starts load the persisted config normally and re-establish the management Link without re-joining
- The `[management]` config section stores Reticule's destination hash and the node's assigned ID

---

## 3. Hot Reload Engine

### 3.1 Config Diff and Application

When a `ConfigPush` arrives:

1. **Backup** current config file
2. **Parse** the incoming config sections
3. **Validate** against known schema (reject unknown keys, invalid value types, out-of-range values)
4. **Diff** against current running config, categorizing each change:

| Change Type | Hot Reloadable | Action |
|---|---|---|
| IFAC credentials (network_name, passphrase, ifac_size) | Yes | Recompute interface IFAC identity and signature in-place |
| Announce rates (target, grace, penalty) | Yes | Update interface properties in-place |
| Interface mode | Yes | Update interface mode property |
| Interface bitrate | Yes | Update interface property |
| Ingress control parameters | Yes | Update in-place |
| Discovery settings (discoverable, etc.) | Yes | Update in-place |
| enable_transport | Targeted | Start/stop Transport participation |
| New interface added | Targeted | Synthesize and register new interface |
| Interface removed | Targeted | Detach and deregister interface |
| Interface type changed | Targeted | Teardown old, synthesize new |
| Interface bind address/port changed | Targeted | Teardown old, synthesize new |
| Shared instance settings | Full restart | Requires daemon restart |

5. **Apply** hot-reloadable changes directly to running interface objects
6. **Execute targeted operations** for interfaces that need teardown/recreation
7. **Write** updated config to disk
8. **Send** `ConfigAck` with resulting config hash and status

### 3.2 Validation Rules

Before applying any config change:

- All referenced interface types must be known
- Port numbers must be in valid range and not conflict with other interfaces or the shared instance port
- IFAC credentials must be non-empty strings if provided
- `ifac_size` must be between 1 and 64 bytes
- `announce_rate_target` must be > 0
- The bootstrap interface (management_protected) must not be modified or removed
- Mode values must be valid (`full`, `gateway`, `ap`, `roaming`, `boundary`)
- At least one non-bootstrap interface must remain enabled

### 3.3 Rollback on Failure

If applying changes fails partway through:

1. Restore previous config file from backup
2. Re-apply previous config to undo partial changes
3. Send `ConfigAck` with status `apply_failed` and error details
4. If restore also fails, log error and continue with whatever state is running — do not crash

---

## 4. State Observation

### 4.1 State Collector

A fiber that runs inside the management module, responsible for sampling runtime state and assembling `NodeStateReport` messages.

**Periodic report** (every 30 seconds, configurable):

- Snapshot all interface stats (rxb, txb, online, peers)
- Snapshot announce table (destination hashes, hops, interface, timestamps)
- Snapshot path table (destination hashes, next hops, hops, interfaces)
- Snapshot active links (destination hashes, status, RTT)
- Compute config hash

**Event-driven reports** (sent immediately, supplementing periodic):

- Interface goes online/offline
- New peer connected/disconnected (TCP/Auto spawned interfaces)
- Config applied (after any ConfigPush)

### 4.2 State Access

The state collector reads from existing Crystal RNS class-level state. No new accessors needed:

| Data | Source |
|---|---|
| Interface list and stats | `Transport.interface_objects` → iterate, read properties |
| Announce table | `Transport.announce_table` → iterate entries |
| Path table | `Transport.path_table` → iterate entries |
| Active links | `Transport.active_links` → iterate, read status/RTT |
| Pending links | `Transport.pending_links` → iterate |
| Config hash | SHA-256 of config file on disk |
| Destinations | `Transport.destinations` → iterate registered destinations |

### 4.3 Announce Table Observation

Register an announce handler (`Transport.register_announce_handler`) that captures all announces for the management module. This gives real-time visibility into:

- New destinations appearing on the network
- Hop count changes (path improvement/degradation)
- Which interface received each announce
- Announce frequency per destination

This data flows into the periodic `NodeStateReport` rather than being sent as separate messages.

---

## 5. Interface Lifecycle Management

### 5.1 Interface Detach (extend existing)

Extend the base `Interface` class `detach()` method to ensure clean teardown:

- Close all sockets/connections
- Stop all associated fibers (read loops, accept loops, keepalive)
- Drain the announce queue
- Remove from Transport's interface list
- For server interfaces: disconnect all spawned client interfaces
- For AutoInterface: leave multicast groups, stop discovery

### 5.2 Interface Hot-Add

New method on `ReticulumInstance`:

```crystal
def add_interface(name : String, config_section : ConfigObj::Section) : Interface
  interface = synthesize_interface(name, config_section)
  interface_post_init(interface, config_section)
  Transport.register_interface(interface.get_hash)
  interface
end
```

### 5.3 Interface Hot-Remove

```crystal
def remove_interface(name : String) : Bool
  interface = Transport.interface_objects.find { |i| i.name == name }
  return false unless interface
  return false if interface.management_protected
  interface.detach
  Transport.deregister_interface(interface.get_hash)
  true
end
```

### 5.4 Interface Hot-Replace

For changes requiring teardown (bind address, port, type):

```crystal
def replace_interface(name : String, new_config : ConfigObj::Section) : Interface
  remove_interface(name)
  add_interface(name, new_config)
end
```

### 5.5 IFAC Hot-Update

For IFAC credential changes (no teardown needed):

```crystal
def update_interface_ifac(name : String, network_name : String?, passphrase : String?, ifac_size : UInt8?) : Bool
  interface = Transport.interface_objects.find { |i| i.name == name }
  return false unless interface
  interface.ifac_netname = network_name
  interface.ifac_netkey = passphrase
  interface.ifac_size = ifac_size || 16_u8
  interface.recompute_ifac_identity
  true
end
```

---

## 6. New Properties on Interface Base Class

```crystal
property management_protected : Bool = false    # bootstrap interface — never modified by ConfigPush
property last_state_change : Float64 = 0.0      # timestamp of last online/offline transition

def recompute_ifac_identity
  # Recompute ifac_key, ifac_identity, ifac_signature from current
  # ifac_netname, ifac_netkey, ifac_size values
  # Mirrors the IFAC computation in Reticulum.interface_post_init:
  #   1. SHA-256 hash network_name and passphrase
  #   2. Concatenate hashes
  #   3. HKDF derive 64-byte key using IFAC_SALT
  #   4. Create Identity from key bytes
  #   5. Compute signature
end
```

---

## 7. New Properties on ReticulumInstance

```crystal
@management : Management::Manager?    # the management module instance (nil if unmanaged)
@bootstrap_interface_name : String?   # name of the protected bootstrap interface

# New config section: [management]
#   enabled = yes                      # whether this node is Reticule-managed
#   reticule_dest_hash = <hex>         # Reticule's management destination hash
#   node_id = <hex>                    # assigned by Reticule during join
#   report_interval = 30               # seconds between state reports
#   heartbeat_interval = 10            # seconds between heartbeats
```

---

## 8. CLI

### 8.1 Join Command

```
crns --join <token_or_url>
```

One command to onboard. Parses the provisioning token, starts the daemon, connects to Reticule, completes the join handshake, writes the resulting config, and enters normal operation.

Token formats accepted:
- Raw base32 token: `crns --join AEBQ4DIZQ...`
- Reticule URL: `crns --join reti://reticule.example.com/join/AEBQ4DIZQ...`
- File path: `crns --join /path/to/token.reti`

### 8.2 Normal Start

```
crns
```

Starts with persisted config. If `[management]` section is present and `enabled = yes`, establishes management Link to Reticule automatically.

### 8.3 Status Extension

```
crns status --management
```

Shows: management link status (connected/disconnected), Reticule destination, last report sent, last config push received, current IFAC configuration per interface.

---

## 9. File Layout

```
crystal/src/rns/management/
  manager.cr               # Top-level management module: lifecycle, Link management, reconnection
  messages.cr              # All message types (NodeStateReport, ConfigPush, ConfigAck,
                           #   Heartbeat, JoinRequest, JoinResponse)
  state_collector.cr       # Periodic and event-driven state sampling, report assembly
  config_engine.cr         # Config diff, validation, hot-reload, rollback
  bootstrap.cr             # Provisioning token parsing, join flow, token formats
```

---

## 10. Non-Goals (v1)

- **Firmware management**: no OTA updates to RNode or other hardware
- **Multi-Reticule**: a node connects to exactly one Reticule instance
- **User application management**: Reticule manages the transport daemon only, not apps on top
- **Direct node-to-node management**: all management flows through Reticule
- **Mesh-based management fallback**: if the Link to Reticule is down, the node operates autonomously with its last-known config
- **Active probing**: Reticule derives reachability from reported announce/path tables, not probes (v2)
- **Segment concept on daemon**: "segments" are a Reticule UI concept; daemon only knows per-interface IFAC credentials

---

## 11. Dependencies on Existing Codebase

No new shard dependencies. All management functionality builds on existing Crystal RNS primitives:

| Primitive | Usage |
|---|---|
| `Destination` | Management destination registration |
| `Link` | Encrypted channel to Reticule |
| `Channel` / `MessageBase` | Structured management protocol |
| `Transport` | State observation, interface registration |
| `Identity` | Node identity, authentication |
| `ConfigObj` | Config file read/write/diff |
| `Interface.detach()` | Interface teardown |
| `ReticulumInstance.synthesize_interface()` | Interface creation from config |
| `ReticulumInstance.interface_post_init()` | Interface post-creation setup (including IFAC) |

---

## 12. What Reticule (Elixir) Handles

For clarity, these responsibilities live in Reticule, NOT in the Crystal daemon:

- **Segment definition**: named groups of IFAC credentials, assigned to interfaces
- **Credential generation and rotation**: Reticule generates passphrases, pushes them via ConfigPush
- **Transport node placement**: Reticule analyzes topology and decides which nodes should be transports
- **Announce rate optimization**: Reticule computes optimal rates based on interface bitrates and topology
- **Interface mode inference**: Reticule decides gateway/ap/full based on node's position
- **Topology analysis**: connectivity, single points of failure, isolated segments, bridge nodes
- **Network map visualization**: rendered from aggregated NodeStateReports
- **Alerting**: node offline, IFAC mismatch detected, convergence issues
