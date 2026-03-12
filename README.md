# RNS — Crystal Port of the Reticulum Network Stack

A complete Crystal implementation of the [Reticulum Network Stack](https://reticulum.network), providing cryptography-based networking for reliable, encrypted, and authenticated communications over any medium.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  rns:
    github: jtippett/rns-cr
    version: ~> 0.1.0
```

Run `shards install`.

## Quick Start

```crystal
require "rns"

# Initialize Reticulum
reticulum = RNS::ReticulumInstance.new(nil)

# Create a new identity (X25519 + Ed25519 key pair)
identity = RNS::Identity.new

# Create a destination
destination = RNS::Destination.new(
  identity,
  RNS::Destination::IN,
  RNS::Destination::SINGLE,
  "example_app",
  "hello"
)

# Announce the destination on the network
destination.announce

# Set up a packet callback
destination.set_packet_callback(->(data : Bytes, packet : RNS::Packet) {
  puts "Received: #{String.new(data)}"
})
```

## API Overview

The Crystal RNS shard exposes the same public API as the Python reference implementation:

| Module | Description |
|--------|-------------|
| `RNS::ReticulumInstance` | Main system class — configuration, startup, and lifecycle |
| `RNS::Identity` | Cryptographic identity management (X25519 + Ed25519) |
| `RNS::Destination` | Named endpoints for sending and receiving packets |
| `RNS::Packet` | Wire-format packet construction, encryption, and hashing |
| `RNS::Link` | Encrypted bidirectional channels via ECDH key exchange |
| `RNS::Channel` | Ordered, reliable message delivery over Links |
| `RNS::Buffer` | Stream-oriented I/O over Channels |
| `RNS::Resource` | Large data transfers with segmentation and flow control |
| `RNS::Transport` | Routing engine — path management, announce handling, tunnels |
| `RNS::Resolver` | Distributed identity resolver (stub for future expansion) |

### Cryptography

All cryptographic primitives are in `RNS::Cryptography`:

- **Hashes** — SHA-256, SHA-512, truncated hashes
- **HMAC** — HMAC-SHA256/512
- **HKDF** — HKDF-SHA256 key derivation (RFC 5869)
- **AES** — AES-256-CBC with PKCS7 padding
- **X25519** — Elliptic-curve Diffie-Hellman key exchange
- **Ed25519** — Digital signatures
- **Token** — Fernet-like authenticated encryption (AES-256-CBC + HMAC-SHA256)

### Interfaces

The full suite of network interfaces is included:

- `UDPInterface` — UDP unicast/broadcast
- `TCPClientInterface` / `TCPServerInterface` — TCP with HDLC framing
- `LocalClientInterface` / `LocalServerInterface` — Unix/local IPC
- `AutoInterface` — Zero-configuration UDP multicast peer discovery
- `SerialInterface` — Serial port with HDLC framing
- `KISSInterface` / `AX25KISSInterface` — KISS and AX.25 amateur radio
- `BackboneInterface` — High-performance backbone links
- `PipeInterface` — External process communication via stdin/stdout
- `I2PInterface` — I2P anonymous network integration
- `RNodeInterface` — LoRa radio via RNode hardware
- `RNodeMultiInterface` — Dual-radio LoRa multiplexing
- `WeaveInterface` — Weave Device Command Language protocol

### CLI Utilities

Binary targets (built with `shards build`):

| Binary | Description |
|--------|-------------|
| `rnsd` | RNS transport daemon |
| `rnstatus` | Display interface and transport status |
| `rnpath` | Path lookup and management |
| `rnprobe` | Network connectivity probe with RTT measurement |
| `rnid` | Identity management (create, import, export, sign, verify) |
| `rncp` | Remote file copy over RNS |
| `rnx` | Remote command execution over RNS |

## Examples

The `examples/` directory contains standalone programs demonstrating the API:

- **minimal.cr** — Basic setup, destination creation, and announcing
- **echo.cr** — Echo server and client
- **announce.cr** — Announce monitoring
- **broadcast.cr** — Broadcast messaging
- **link.cr** — Encrypted link establishment
- **request.cr** — Request/response pattern
- **identify.cr** — Identity verification over links
- **channel.cr** — Channel-based ordered messaging
- **buffer.cr** — Stream I/O over channels
- **resource.cr** — Resource transfers
- **filetransfer.cr** — File transfer over links
- **speedtest.cr** — Performance benchmarking
- **ratchets.cr** — Forward secrecy with ratchets

Run an example:

```sh
crystal run examples/minimal.cr
```

## Protocol Compatibility

This implementation is wire-compatible with the Python Reticulum Network Stack. Key protocol constants match exactly:

- MTU: 500 bytes
- Truncated hash length: 128 bits (16 bytes)
- Identity key size: 512 bits (256 encryption + 256 signing)
- X25519 key: 32 bytes
- Ed25519 signature: 64 bytes
- Token overhead: 48 bytes

## Development

### Spec Safety Warning

Some specs (stress tests, multi-instance tests) bind to all local network interfaces and can cause network instability or OS crashes on macOS. Avoid running these directly:

```sh
# Safe: run unit specs only
crystal spec spec/rns/

# Unsafe: stress tests and multi-instance specs that bind all local interfaces
# These can destabilize networking or crash macOS — run only in a VM or container
```

Always restrict `AutoInterface` to loopback when running tests locally. If you experience network issues after a spec run, a reboot may be required.

### Running specs

Run the test suite:

```sh
crystal spec
```

Run the linter:

```sh
bin/ameba
```

Generate API documentation:

```sh
crystal docs
```

Build all binaries:

```sh
shards build
```

**Important:** See the [network impact warning](../PRD.md#caution-network-impact-during-testing) in the PRD before running specs. Always restrict `AutoInterface` to loopback in tests.

## Dependencies

- [ed25519](https://github.com/spider-gazelle/ed25519) — Ed25519 signatures
- [qr-code](https://github.com/spider-gazelle/qr-code) — QR code generation
- [HKDF](https://github.com/spider-gazelle/HKDF) — HKDF key derivation
- [msgpack-crystal](https://github.com/crystal-community/msgpack-crystal) — MessagePack serialization
- [bindata](https://github.com/spider-gazelle/bindata) — Binary data handling

Crystal stdlib provides: OpenSSL (AES, HMAC, SHA, X25519), TCP/UDP sockets, fibers/channels, INI parsing.

## License

MIT
