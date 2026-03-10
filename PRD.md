# PRD: Crystal Port of Reticulum Network Stack

## Overview

Port the complete Reticulum Network Stack (RNS) from Python to Crystal, producing a high-quality, fully tested and compatible Crystal shard that can be imported and used in Crystal programs as a drop-in networking option. The Python reference implementation lives in `RNS/` — read the corresponding Python source when implementing each module.

## Architecture

```

  shard.yml
  src/
    rns.cr                          # Main entry, re-exports public API
    rns/
      version.cr
      log.cr                        # Logging (log levels, formatting)
      cryptography/
        provider.cr                 # Crypto backend selection
        hashes.cr                   # SHA-256, SHA-512
        hmac.cr                     # HMAC-SHA256/512
        hkdf.cr                     # HKDF key derivation
        pkcs7.cr                    # PKCS7 padding
        aes.cr                      # AES-256-CBC
        x25519.cr                   # X25519 ECDH key exchange
        ed25519.cr                  # Ed25519 signatures (wraps shard)
        token.cr                    # Fernet-like authenticated encryption
      identity.cr
      packet.cr
      destination.cr
      transport.cr
      transport/
        path_management.cr          # Path table, path discovery
        announce_handler.cr         # Announce processing, rate limiting
        tunnel_management.cr        # Tunnel creation and maintenance
      link.cr
      channel.cr
      resource.cr
      buffer.cr
      resolver.cr
      discovery.cr
      reticulum.cr                  # Main system class, config, startup
      interfaces/
        interface.cr                # Base class
        udp_interface.cr
        tcp_interface.cr
        local_interface.cr
        auto_interface.cr
        serial_interface.cr
        kiss_interface.cr
        ax25_kiss_interface.cr
        backbone_interface.cr
        pipe_interface.cr
        i2p_interface.cr
        rnode_interface.cr
        rnode_multi_interface.cr
        weave_interface.cr
      vendor/
        platform_utils.cr
        config_obj.cr               # INI-style config parser
        msgpack.cr                  # MessagePack helpers/wrappers
  spec/
    spec_helper.cr
    rns/
      cryptography/
        hashes_spec.cr
        hmac_spec.cr
        hkdf_spec.cr
        pkcs7_spec.cr
        aes_spec.cr
        x25519_spec.cr
        ed25519_spec.cr
        token_spec.cr
      identity_spec.cr
      packet_spec.cr
      destination_spec.cr
      transport_spec.cr
      link_spec.cr
      channel_spec.cr
      resource_spec.cr
      buffer_spec.cr
      reticulum_spec.cr
      interfaces/
        interface_spec.cr
        udp_interface_spec.cr
        tcp_interface_spec.cr
        local_interface_spec.cr
        auto_interface_spec.cr
      integration/
        announce_spec.cr
        link_establishment_spec.cr
        file_transfer_spec.cr
        multi_interface_spec.cr
```

## Dependencies (shard.yml)

```yaml
dependencies:
  ed25519:
    github: spider-gazelle/ed25519
    version: ~> 1.0
  qr-code:
    github: spider-gazelle/qr-code
  hkdf:
    github: spider-gazelle/HKDF
  msgpack:
    github: crystal-community/msgpack-crystal
  bindata:
    github: spider-gazelle/bindata

development_dependencies:
  ameba:
    github: crystal-ameba/ameba
```

Crystal stdlib provides: OpenSSL (AES-256-CBC, HMAC, SHA-256/512, X25519 via EVP), TCP/UDP sockets, fibers/channels, INI parsing.

## Key Porting Notes

- Python `threading.Thread` → Crystal `spawn` (fibers)
- Python `queue.Queue` → Crystal `Channel`
- Python `threading.Lock` → Crystal `Mutex` (only when needed; fibers are cooperative)
- Python `struct.pack/unpack` → Crystal `IO::Memory` with `read_bytes`/`write_bytes` + `IO::ByteFormat`
- Python `umsgpack` → `MessagePack` shard
- Python `configobj` → Crystal `INI` stdlib or custom parser matching RNS config format
- Python `time.time()` → Crystal `Time.utc.to_unix_f`
- Python `os.urandom(n)` → Crystal `Random::Secure.random_bytes(n)`
- Python `hashlib` → Crystal `OpenSSL::Digest` or `Digest::SHA256`
- Python classes with `__init__` → Crystal classes with `initialize`
- Python `None` → Crystal `nil` (use nilable types `Type?`)
- Maintain exact same constants, MTU values, hash lengths, and protocol behavior
- All public API methods must match the Python API semantics

## Constants Reference (must match exactly)

- MTU: 500 bytes
- Truncated hash length: 128 bits (16 bytes)
- Identity key size: 512 bits (256 encryption + 256 signing)
- Identity hash length: 256 bits
- Name hash length: 80 bits
- Ratchet size: 256 bits
- Token overhead: 48 bytes
- X25519 key: 32 bytes
- Ed25519 signature: 64 bytes
- Header min size: 19 bytes
- Header max size: 35 bytes
- Encrypted MDU: ~367 bytes
- Plain MDU: ~463 bytes
- Link MDU: ~383 bytes
- Link establishment timeout per hop: 6 seconds
- Link keepalive: 360 seconds
- Link stale time: 720 seconds
- Resource initial window: 4 segments
- Resource max window (fast): 75 segments
- Resource max efficient size: 16 MB

---

## Tasks

### Phase 1: Project Foundation

- [x] **1.1 — Initialize Crystal shard project**
  Create `` directory. Initialize with `shard.yml` (name: `rns`, version: 0.1.0, crystal >= 1.9.0). Add all dependencies listed above. Create `src/rns.cr` entry point with module `RNS` and version constant. Create `src/rns/version.cr`. Create `spec/spec_helper.cr`. Create `.gitignore` for Crystal (`lib/`, `.shards/`, `bin/`). Run `shards install` to verify dependencies resolve. Write a trivial spec that requires the library and passes.

- [x] **1.2 — Logging and utility infrastructure**
  Port `RNS/__init__.py` logging system → `src/rns/log.cr`. Implement log levels: `LOG_CRITICAL` (0), `LOG_ERROR` (1), `LOG_WARNING` (2), `LOG_NOTICE` (3), `LOG_INFO` (4), `LOG_VERBOSE` (5), `LOG_DEBUG` (6), `LOG_EXTREME` (7). Implement `RNS.log(message, level, _override_destination)` with configurable log destination and level. Port `hexrep()`, `prettysize()`, `prettytime()`, `phyparams()`, `panic()` utility functions. Also create `src/rns/vendor/platform_utils.cr` with OS detection (map Python's `platformutils`). Write specs for all utility functions.

### Phase 2: Cryptography Layer

Read `RNS/Cryptography/` for reference. Every crypto module must have specs with known test vectors.

- [x] **2.1 — Hashes: SHA-256 and SHA-512**
  Create `src/rns/cryptography/hashes.cr`. Wrap Crystal's `OpenSSL::Digest` to provide `RNS::Cryptography.sha256(data : Bytes) : Bytes` and `RNS::Cryptography.sha512(data : Bytes) : Bytes`. Port the truncated hash helper used throughout RNS. Write specs using NIST test vectors from `tests/hashes.py` and add random roundtrip tests (1000+ iterations comparing against OpenSSL directly).

- [x] **2.2 — HMAC and HKDF**
  Create `src/rns/cryptography/hmac.cr` wrapping `OpenSSL::HMAC` to provide `RNS::Cryptography::HMAC.digest(key, data, algorithm)`. Create `src/rns/cryptography/hkdf.cr` using the `hkdf` shard (spider-gazelle/HKDF) to provide `RNS::Cryptography::HKDF.derive_key(ikm, length, salt, info)`. Match the Python HKDF interface exactly — read `RNS/Cryptography/HKDF.py`. Write specs with RFC 5869 test vectors.

- [x] **2.3 — PKCS7 padding and AES-256-CBC**
  Create `src/rns/cryptography/pkcs7.cr` — implement PKCS7 `pad(data, block_size)` and `unpad(data)`. Read `RNS/Cryptography/PKCS7.py` for reference. Create `src/rns/cryptography/aes.cr` wrapping `OpenSSL::Cipher` — provide `encrypt(plaintext, key, iv)` and `decrypt(ciphertext, key, iv)` for AES-256-CBC with PKCS7 padding. Write specs: roundtrip encryption, known test vectors, invalid padding detection.

- [x] **2.4 — X25519 key exchange**
  Create `src/rns/cryptography/x25519.cr`. Use Crystal's OpenSSL bindings to access X25519 via EVP_PKEY API (OpenSSL 1.1.1+). Implement `X25519PrivateKey` and `X25519PublicKey` classes matching the Python API in `RNS/Cryptography/X25519.py`: `generate()`, `from_private_bytes(data)`, `private_bytes()`, `public_key()`, `exchange(peer_public_key)`. Write specs: key generation, key exchange between two parties produces same shared secret, known test vectors from RFC 7748.

- [x] **2.5 — Ed25519 signatures**
  Create `src/rns/cryptography/ed25519.cr`. Wrap the `spider-gazelle/ed25519` shard. Implement `Ed25519PrivateKey` and `Ed25519PublicKey` classes matching `RNS/Cryptography/Ed25519.py`: `generate()`, `from_private_bytes(data)`, `private_bytes()`, `public_key()`, `sign(message)`, `verify(signature, message)`. Write specs: sign/verify roundtrip, invalid signature rejection, key serialization roundtrip, RFC 8032 test vectors.

- [x] **2.6 — Token (Fernet-like authenticated encryption)**
  Create `src/rns/cryptography/token.cr`. Port `RNS/Cryptography/Token.py` exactly. Implement `Token` class with `TOKEN_OVERHEAD` constant (48 bytes), `generate_key()`, `encrypt(plaintext, key)`, `decrypt(ciphertext, key)`, `verify_hmac(token, key)`. This uses AES-256-CBC + HMAC-SHA256. Write specs: roundtrip encrypt/decrypt, tampering detection, overhead constant verification. Create `src/rns/cryptography/provider.cr` that re-exports all crypto modules.

### Phase 3: Core Protocol

- [x] **3.1 — Identity module**
  Port `RNS/Identity.py` (821 LOC) → `src/rns/identity.cr`. Key constants: `CURVE = "Curve25519"`, `KEYSIZE = 512` (bits), `HASHLENGTH = 256`, `NAME_HASH_LENGTH = 80`, `RATCHETSIZE = 256`, `RATCHET_EXPIRY`, `TRUNCATED_HASHLENGTH = 128`. Implement `Identity` class: `create_keys()`, `get_private_key()`, `load_private_key(data)`, `load_public_key(data)`, `encrypt(plaintext)`, `decrypt(ciphertext)`, `sign(message)`, `validate(signature, message)`, `prove(packet, destination)`, `hash()`, `hexhash()`, `from_bytes(data)`, `from_file(path)`, `to_file(path)`. Implement static methods: `remember(packet_hash, destination_hash, public_key, app_data)`, `recall(destination_hash)`, `recall_app_data(destination_hash)`, `save_known_destinations()`, `load_known_destinations(path)`, `full_hash(data)`, `truncated_hash(data)`, `get_random_hash()`. Handle the known_destinations and known_ratchets class-level state. Write thorough specs: key generation, sign/verify, encrypt/decrypt, hash computation, recall/remember, serialization.

- [x] **3.2 — Packet module**
  Port `RNS/Packet.py` (602 LOC) → `src/rns/packet.cr`. Define all packet type constants: `DATA = 0x00`, `ANNOUNCE = 0x01`, `LINKREQUEST = 0x02`, `PROOF = 0x03`. Define header types: `HEADER_1 = 0x00`, `HEADER_2 = 0x01`. Define transport types, context types. Implement `Packet` class: `initialize(destination, data, packet_type, context, transport_type, header_type, transport_id, attached_interface, create_receipt)`, `pack()`, `unpack()`, `encrypt()`, `decrypt()`, `send()`, `resend()`, `prove(destination)`, `update_hash()`, `get_hash() : Bytes`. Implement `PacketReceipt` class with callbacks: `set_timeout(callback, timeout)`, `set_delivery_callback(callback)`, status tracking. Implement `ProofDestination` class. Port the MTU/MDU constants: `ENCRYPTED_MDU`, `PLAIN_MDU`, `HEADER_MINSIZE`, `HEADER_MAXSIZE`. Write specs: packet creation, pack/unpack roundtrip, hash computation, header encoding correctness, MTU boundary tests.

- [x] **3.3 — Destination module**
  Port `RNS/Destination.py` (691 LOC) → `src/rns/destination.cr`. Define types: `SINGLE = 0x00`, `GROUP = 0x01`, `PLAIN = 0x02`, `LINK = 0x03`. Define directions: `IN = 0x11`, `OUT = 0x12`. Define proof strategies: `PROVE_NONE`, `PROVE_APP`, `PROVE_ALL`. Implement `Destination` class: `initialize(identity, direction, type, app_name, *aspects)`, `hash()`, `hexhash()`, `announce(app_data, path_response, attached_interface, tag, send)`, `accepts_links?`, `set_link_established_callback(callback)`, `set_packet_callback(callback)`, `set_proof_requested_callback(callback)`, `set_proof_strategy(strategy)`, `register_request_handler(path, response_generator, allow, allowed_list)`, `encrypt(plaintext)`, `decrypt(ciphertext)`, `sign(message)`. Handle ratchets: `RATCHET_COUNT`, `RATCHET_INTERVAL`, rotating ratchet keys. Wire registration with `Transport.register_destination()`. Write specs: destination creation, hash derivation matches Python behavior, encryption/decryption, announce generation.

### Phase 4: Transport Layer

This is the largest module (3312 LOC). Split into manageable sub-modules.

- [x] **4.1 — Transport core and data structures**
  Create `src/rns/transport.cr` and `src/rns/transport/path_management.cr`. Port the Transport class skeleton from `RNS/Transport.py`. Define all constants: `BROADCAST = 0x00`, `TRANSPORT = 0x01`, `RELAY = 0x02`, `TUNNEL = 0x03`, `REACHABILITY_UNREACHABLE/DIRECT/TRANSPORT`, `PATHFINDER_M`, `PATHFINDER_R`, `PATHFINDER_G`, `PATHFINDER_RW`, expiry times, rate limits. Set up core state: `@@interfaces`, `@@destinations`, `@@pending_links`, `@@active_links`, `@@packet_hashlist`, `@@receipts`, `@@announce_table`, `@@destination_table`, `@@path_table`, `@@reverse_table`, `@@tunnel_table`, `@@link_table`. Implement `register_destination(destination)`, `deregister_destination(destination)`, `register_interface(interface)`, `deregister_interface(interface)`, `has_path(destination_hash)`, `hops_to(destination_hash)`, `next_hop(destination_hash)`, `next_hop_interface(destination_hash)`, `expire_path(destination_hash)`, `request_path(destination_hash, on_interface, tag, recursive)`. Implement path table persistence: `save_path_table()`, `load_path_table()`. Write specs for path management: register/deregister, path lookup, expiry.

- [x] **4.2 — Transport announce handling**
  Create `src/rns/transport/announce_handler.cr`. Port announce processing from `RNS/Transport.py`: `inbound_announce(raw, packet, interface)`, `outbound_announce(announce)`, `process_announce_queue(interface)`, `should_forward_announce(announce, interface)`, `mark_path_unknown_for_destination(destination_hash)`, rate limiting logic, announce deduplication, announce validation. Handle the announce table: entry creation, expiry, retransmission timing. Handle path responses. Write specs: announce validation, rate limiting, deduplication, forwarding decisions.

- [x] **4.3 — Transport packet routing and delivery**
  Complete `src/rns/transport.cr` with packet routing: `inbound(raw, interface)`, `outbound(packet)`, `forward(packet)`, `transmit(interface, raw)`, `internal_inbound(raw, interface)`. Implement link management: `register_link(link)`, `activate_link(link)`, `find_link_for_request_packet(packet)`, `find_best_link(destination_hash)`. Implement tunnel management in `src/rns/transport/tunnel_management.cr`: `register_tunnel(tunnel_id, interface)`, `tunnel_synthesize_handler()`. Implement the transport job loop: `jobs_locked`, periodic path/link/receipt expiry, cache cleaning. Write specs: packet routing decisions, link registration, receipt handling.

- [x] **4.4 — Transport caching and persistence**
  Implement Transport caching: `cache(packet, force_cache)`, packet hash deduplication, cache file storage. Implement `save_packet_hashlist()`, `load_packet_hashlist()`. Implement `save_tunnel_table()`, `load_tunnel_table()`. Implement `owner` references and the `start(reticulum_instance)` initialization method. Wire up the periodic job fiber that runs `jobs()`. Ensure all Transport state is properly synchronized with `Mutex` where needed for fiber safety. Write integration specs: cache persistence roundtrip, packet hashlist save/load, tunnel table persistence.

### Phase 5: Communication Layer

- [x] **5.1 — Channel module**
  Port `RNS/Channel.py` (705 LOC) → `src/rns/channel.cr`. Define enums: `CEType` (exception types), `MessageState` (MSGSTATE_NEW, SENT, DELIVERED, FAILED). Implement abstract `ChannelOutletBase` (Crystal abstract class). Implement `MessageBase` abstract class with `pack()`, `unpack()`, `MSGTYPE` identification. Implement `Envelope` class: wraps messages with sequence numbers, timestamps, retry tracking. Implement `Channel` class: `send(message)`, `register_message_type(msg_type)`, `add_message_handler(callback)`, `remove_message_handler(callback)`, `get_mdu()`, `is_ready_to_send?`. Implement `LinkChannelOutlet` (concrete outlet using Link). Handle message ordering, delivery confirmation, retry logic, and windowing. Implement `SystemMessageTypes`. Write specs: message serialization, ordering, delivery confirmation, windowing behavior.

- [x] **5.2 — Link module — establishment and encryption**
  Port `RNS/Link.py` (1549 LOC, part 1) → `src/rns/link.cr`. Define all constants: `CURVE = "Curve25519"`, `ECPUBSIZE = 32`, `KEYSIZE = 512`, modes (`MODE_AES256_CBC = 0x00`, `MODE_AES256_GCM = 0x01`, `MODE_PQ_*`), states (`PENDING`, `HANDSHAKE`, `ACTIVE`, `STALE`, `CLOSED`), timeouts, keepalive intervals, stale times. Implement `Link` class constructor and the 3-step ECDH handshake: (1) initiator generates ephemeral X25519 keypair and sends link request, (2) responder validates, generates own ephemeral keypair, derives shared secret, sends proof, (3) initiator verifies proof and derives same shared secret. Implement `derive_keys()` using HKDF to produce symmetric encryption keys from the ECDH shared secret. Implement `encrypt(plaintext)`, `decrypt(ciphertext)` using the derived keys. Implement `identify(identity)` and `request(path, data, response_callback, failed_callback, progress_callback, timeout)`. Write specs: key exchange produces matching shared secrets, encrypt/decrypt roundtrip, link state transitions.

- [x] **5.3 — Link module — lifecycle management**
  Complete `src/rns/link.cr`. Implement `send(data, packet_type, context)`, `receive(packet)`, `prove(packet, destination)`, `prove_packet(packet)`, `validate_proof(packet)`. Implement keepalive: `watchdog()` fiber, `send_keepalive()`, keepalive response handling. Implement teardown: `teardown()`, `teardown_packet(packet)`. Implement RTT tracking: `rtt`, `set_resource_strategy(strategy, callback)`. Implement `track_phy_stats(raw)`. Implement `inactive_for()`, `no_inbound_for()`, `no_outbound_for()`, `no_data_for()`. Handle stale detection and automatic teardown. Implement `resource_concluded(resource)` for Resource integration. Wire `LinkCallbacks` and `RequestReceipt`/`RequestReceiptCallbacks`. Write specs: keepalive timing, stale detection, teardown, RTT computation.

- [x] **5.4 — Resource module**
  Port `RNS/Resource.py` (1361 LOC) → `src/rns/resource.cr`. Implement `Resource` class for large data transfers over Links. Constants: `WINDOW = 4`, `WINDOW_MIN = 2`, `WINDOW_MAX = 75`, `WINDOW_MAX_SLOW = 10`, `RATE_FAST/MEDIUM/SLOW/VERY_SLOW`, `MAX_EFFICIENT_SIZE = 16_777_215`, `AUTO_COMPRESS_MAX_SIZE`, `MAX_RETRIES`, `SENDER_GRACE_TIME`, `MAX_ADV_RETRIES`. States: `QUEUED`, `ADVERTISED`, `TRANSFERRING`, `AWAITING_PROOF`, `COMPLETE`, `FAILED`, `CORRUPT`. Implement sender side: `advertise()`, `send_part()`, segmentation, window management, adaptive rate control. Implement receiver side: `accept(sender_identity)`, `reject()`, `cancel()`, reassembly, proof generation. Implement `ResourceAdvertisement` class: `pack()`, `unpack()`, hash verification. Handle bz2 compression for data segments. Write specs: segmentation/reassembly roundtrip, window growth/shrink, compression behavior, advertisement pack/unpack.

### Phase 6: High-Level Modules

- [x] **6.1 — Buffer module**
  Port `RNS/Buffer.py` (369 LOC) → `src/rns/buffer.cr`. Implement `StreamDataMessage` (a Channel MessageBase for stream data). Implement `RawChannelReader` (reads from a Channel, implements `IO` interface). Implement `RawChannelWriter` (writes to a Channel, implements `IO` interface). Implement `Buffer` module with class methods: `create_reader(stream_id, channel, ready_callback)`, `create_writer(stream_id, channel)`, `create_bidirectional_buffer(stream_id_in, stream_id_out, channel, ready_callback)`. Wire buffering, flow control, and close semantics. Write specs: read/write roundtrip through channel, bidirectional buffer, flow control behavior.

- [x] **6.2 — Resolver module (stub)**
  Port `RNS/Resolver.py` (34 LOC) → `src/rns/resolver.cr`. This is currently a stub/placeholder in the Python version. Implement the `Resolver` class with the same interface as Python. If the Python version has any implemented functionality, port it. Otherwise, create the class with the correct interface for future expansion. Write a basic spec.

### Phase 7: Interface System

- [x] **7.1 — Interface base class**
  Port `RNS/Interfaces/Interface.py` (302 LOC) → `src/rns/interfaces/interface.cr`. Define abstract `Interface` class. Constants: `IN = 0`, `OUT = 1`, `FWD = 2`, `RPT = 3`, mode flags (`MODE_FULL`, `MODE_POINT_TO_POINT`, `MODE_ACCESS_POINT`, `MODE_ROAMING`, `MODE_BOUNDARY`, `MODE_GATEWAY`), MTU types (`AUTOCONFIGURE_MTU`, `FIXED_MTU`, `HW_MTU`). Properties: `name`, `rxb`, `txb`, `online`, `bitrate`, `mtu`, `announce_rate_target`, `announce_rate_grace`, `announce_rate_penalty`, `ifac_size`, `held_announces`. Implement: `get_hash()`, `should_ingress_limit()`, `optimise_mtu()`, `age()`, `hold_announce()`, `process_held_announces()`, `received_announce()`, `sent_announce()`, `incoming_announce_frequency()`, `outgoing_announce_frequency()`, `process_announce_queue()`, `final_init()`, `detach()`. Implement HDLC framing helpers (used by multiple interfaces) and IFAC (Interface Authentication Code) validation. Write specs: hash computation, announce rate limiting, MTU optimization.

- [x] **7.2 — UDP interface**
  Port `RNS/Interfaces/UDPInterface.py` (140 LOC) → `src/rns/interfaces/udp_interface.cr`. Implement `UDPInterface` class using Crystal `UDPSocket`. Support: bind address/port, target address/port, broadcast mode. Implement `process_outgoing(data)` and the receive fiber. Handle configuration from config object. Write specs: send/receive over localhost UDP, configuration parsing.

- [x] **7.3 — TCP interface (client and server)**
  Port `RNS/Interfaces/TCPInterface.py` (661 LOC) → `src/rns/interfaces/tcp_interface.cr`. Implement `TCPClientInterface` and `TCPServerInterface`. Client: connect to host:port, HDLC framing, reconnection logic, keepalive. Server: accept connections, manage client list, threading via fibers. Handle connection timeouts, graceful disconnection, data framing with HDLC escape sequences. Write specs: client/server communication over localhost, HDLC framing roundtrip, reconnection behavior.

- [x] **7.4 — Local interface**
  Port `RNS/Interfaces/LocalInterface.py` (472 LOC) → `src/rns/interfaces/local_interface.cr`. Implement `LocalClientInterface` and `LocalServerInterface`. These use Unix domain sockets or TCP localhost for inter-process communication within the same machine. Support shared instance mode (multiple programs sharing one RNS transport instance). Write specs: local client/server communication, multi-client handling.

- [x] **7.5 — Auto interface (peer discovery)**
  Port `RNS/Interfaces/AutoInterface.py` (663 LOC) → `src/rns/interfaces/auto_interface.cr`. Implement `AutoInterface` with UDP multicast peer discovery. Handle: multicast group management, peer tracking (`AutoInterfacePeer`), link-local addressing, automatic peer connection/disconnection, data scope management. This is critical for zero-configuration networking. Write specs: peer discovery simulation, multicast group handling.

- [ ] **7.6 — Serial interface**
  Port `RNS/Interfaces/SerialInterface.py` (227 LOC) → `src/rns/interfaces/serial_interface.cr`. Implement `SerialInterface` for generic serial port communication. Use HDLC framing over serial. Handle baud rate configuration, port opening/closing, read/write with proper byte-level handling. Note: may need to add `serialport` shard dependency or use direct POSIX termios bindings. Write specs: HDLC framing roundtrip (can test without hardware using IO pipes).

- [ ] **7.7 — KISS and AX.25 KISS interfaces**
  Port `RNS/Interfaces/KISSInterface.py` (387 LOC) → `src/rns/interfaces/kiss_interface.cr`. Port `RNS/Interfaces/AX25KISSInterface.py` (400 LOC) → `src/rns/interfaces/ax25_kiss_interface.cr`. Implement KISS protocol framing: FEND (0xC0), FESC (0xDB), TFEND (0xDC), TFESC (0xDD), command bytes. AX.25 adds amateur radio addressing (callsigns, SSIDs) on top of KISS. Write specs: KISS frame encoding/decoding, AX.25 address formatting, roundtrip framing.

- [ ] **7.8 — Backbone interface**
  Port `RNS/Interfaces/BackboneInterface.py` (697 LOC) → `src/rns/interfaces/backbone_interface.cr`. Implement `BackboneInterface` and `BackboneClientInterface` for high-performance network backbone links. Support TCP and UDP modes, connection multiplexing, performance optimization for high-bandwidth links. Write specs: backbone connection establishment, data transfer.

- [ ] **7.9 — Pipe interface**
  Port `RNS/Interfaces/PipeInterface.py` (205 LOC) → `src/rns/interfaces/pipe_interface.cr`. Implement `PipeInterface` that communicates with external programs via stdin/stdout pipes. Handle process spawning, bidirectional pipe I/O, process lifecycle management. Write specs: pipe communication with a simple echo subprocess.

- [ ] **7.10 — I2P interface**
  Port `RNS/Interfaces/I2PInterface.py` (1009 LOC) → `src/rns/interfaces/i2p_interface.cr`. Implement `I2PInterface`, `I2PInterfacePeer`, and `I2PController`. Handle SAM (Simple Anonymous Messaging) protocol for communicating with the I2P router. Support tunnel creation, destination management, session handling. This is complex — the Python version uses asyncio internally. Map to Crystal fibers. Write specs: SAM protocol message formatting, session state management (can test protocol logic without running I2P daemon).

- [ ] **7.11 — RNode interface (LoRa)**
  Port `RNS/Interfaces/RNodeInterface.py` (1558 LOC) → `src/rns/interfaces/rnode_interface.cr`. Implement `RNodeInterface` for LoRa radio communication via RNode hardware. Handle: KISS-based command protocol, radio parameter configuration (frequency, bandwidth, spreading factor, coding rate, TX power), firmware detection, statistics tracking, connection management over serial. This is the most complex interface. Write specs: command encoding/decoding, radio parameter validation, KISS command framing.

- [ ] **7.12 — RNode Multi and Weave interfaces**
  Port `RNS/Interfaces/RNodeMultiInterface.py` (1148 LOC) → `src/rns/interfaces/rnode_multi_interface.cr`. Implement `RNodeMultiInterface` and `RNodeSubInterface` for dual-radio LoRa setups with interface multiplexing. Port `RNS/Interfaces/WeaveInterface.py` (1091 LOC) → `src/rns/interfaces/weave_interface.cr`. Implement `WeaveInterface`, `WeaveInterfacePeer`, and Weave Device Command Language (WDCL) protocol. Write specs for both: command protocols, multiplexing logic.

### Phase 8: System Integration

- [ ] **8.1 — Configuration parser**
  Create `src/rns/vendor/config_obj.cr`. Port the configuration file parsing that `RNS/Reticulum.py` uses. RNS configs use an INI-like format via `configobj`. Crystal has `INI` in stdlib — evaluate if it's sufficient or if a custom parser is needed to match RNS config format (which supports nested sections and type coercion). Handle: reading config files, creating default configs, interface section parsing. Write specs with sample RNS config files.

- [ ] **8.2 — Reticulum main class — initialization and configuration**
  Port `RNS/Reticulum.py` (1716 LOC, part 1) → `src/rns/reticulum.cr`. Implement `Reticulum` class as singleton. Handle: configuration directory detection (`~/.reticulum/` or custom), config file parsing, storage/cache/resource path management. Constants: `MAX_QUEUED_ANNOUNCES`, connection modes. Implement `initialize(configdir, loglevel, logdest, verbosity)`: load config, set up paths, initialize Identity known destinations, start Transport. Implement `create_default_config()`. Write specs: initialization, path management, default config generation.

- [ ] **8.3 — Reticulum main class — interface instantiation and lifecycle**
  Complete `src/rns/reticulum.cr`. Implement interface instantiation from config: for each `[[interface_name]]` section, determine type and create the appropriate Interface subclass with parsed configuration. Implement `start_local_interface()`, `start_remote_interface()`. Implement exit handler: `exit_handler()` — save state (path tables, known destinations, packet hashlist), teardown interfaces, stop Transport. Wire `at_exit` hook. Handle shared instance mode (daemon). Write specs: interface instantiation from config, exit handler saves state.

- [ ] **8.4 — Discovery module**
  Port `RNS/Discovery.py` (733 LOC) → `src/rns/discovery.cr`. Implement `InterfaceAnnouncer` (creates and sends discovery announces for interfaces). Implement `InterfaceAnnounceHandler` (receives and processes discovery announces). Implement `InterfaceDiscovery` (coordinates discovery across all interfaces). Implement `BlackholeUpdater` (manages network blackhole detection and distribution). Handle: encrypted discovery announces, peer interface auto-connection, blackhole list publishing. Write specs: announce creation/validation, discovery state management, blackhole list handling.

### Phase 9: Public API and Module Integration

- [ ] **9.1 — Wire up public API in src/rns.cr**
  Update `src/rns.cr` to require all modules in correct order (respecting the dependency graph). Export the public API matching Python's `RNS.__init__`: `RNS::Reticulum`, `RNS::Identity`, `RNS::Destination`, `RNS::Transport`, `RNS::Packet`, `RNS::Link`, `RNS::Channel`, `RNS::Buffer`, `RNS::Resource`, `RNS::Resolver`. Ensure `RNS.log()`, `RNS.version()`, `RNS.host_os()`, `RNS.hexrep()`, etc. are accessible at module level. Add convenience type aliases where helpful for Crystal ergonomics. Write a comprehensive spec that exercises the full public API surface — import the library, create an Identity, create a Destination, verify the module re-exports work.

- [ ] **9.2 — Cross-module integration testing**
  Create `spec/rns/integration/`. Write integration specs that test the full stack working together: (1) `announce_spec.cr` — create Reticulum instance with LocalInterface, create Identity, create Destination, send announce, verify Transport processes it. (2) `link_establishment_spec.cr` — two Reticulum instances connected via LocalInterface, establish a Link between them, verify ECDH handshake completes, send data over the link. (3) `file_transfer_spec.cr` — transfer a Resource (file) over an established Link, verify data integrity. (4) `multi_interface_spec.cr` — test routing across multiple interfaces. Reference `tests/link.py` and `tests/channel.py` from the Python codebase for test patterns.

### Phase 10: Utilities and CLI Tools

- [ ] **10.1 — rnsd daemon**
  Port `RNS/Utilities/rnsd.py` (564 LOC) → Crystal CLI binary target. Add a `targets` section to `shard.yml` for `rnsd`. Implement: argument parsing (config dir, log level, daemon mode), Reticulum initialization, signal handling (SIGINT, SIGTERM for graceful shutdown), background execution. This is the core daemon that runs the RNS transport layer. Write integration spec that starts/stops the daemon.

- [ ] **10.2 — rnstatus and rnpath utilities**
  Port `RNS/Utilities/rnstatus.py` (687 LOC) → `rnstatus` binary target. Display interface status, transport stats, announce table, path table. Port `RNS/Utilities/rnpath.py` (548 LOC) → `rnpath` binary target. Path lookup, path request, path table display. Both connect to a running rnsd instance. Write basic specs for output formatting.

- [ ] **10.3 — rnprobe and rnid utilities**
  Port `RNS/Utilities/rnprobe.py` (251 LOC) → `rnprobe` binary target. Network connectivity probe — send probe packet, measure RTT. Port `RNS/Utilities/rnid.py` (611 LOC) → `rnid` binary target. Identity management: create, import, export identities; sign/verify data; encrypt/decrypt. Integrate the `qr-code` shard for QR code generation of identity hashes. Write specs for identity operations.

- [ ] **10.4 — rncp and rnx utilities**
  Port `RNS/Utilities/rncp.py` (906 LOC) → `rncp` binary target. Remote file copy over RNS — uses Resources for file transfer. Port `RNS/Utilities/rnx.py` (740 LOC) → `rnx` binary target. Remote command execution over RNS — uses Links for encrypted command channels. Write specs for argument parsing and protocol message formatting.

### Phase 11: Examples and Documentation

- [ ] **11.1 — Port core examples**
  Port `Examples/Minimal.py`, `Examples/Echo.py`, `Examples/Announce.py`, `Examples/Broadcast.py` → `examples/`. Each example should be a standalone Crystal program demonstrating the API. Ensure examples compile and can run with a local Reticulum instance.

- [ ] **11.2 — Port advanced examples**
  Port `Examples/Link.py`, `Examples/Request.py`, `Examples/Identify.py`, `Examples/Channel.py`, `Examples/Buffer.py` → `examples/`. These demonstrate encrypted links, request/response patterns, identity verification, and channel/buffer usage.

- [ ] **11.3 — Port file transfer and performance examples**
  Port `Examples/Resource.py`, `Examples/Filetransfer.py`, `Examples/Speedtest.py`, `Examples/Ratchets.py` → `examples/`. These demonstrate large file transfers, performance testing, and forward secrecy with ratchets.

### Phase 12: Quality and Compatibility

- [ ] **12.1 — Protocol compatibility verification**
  Write cross-language compatibility tests. Create test fixtures: known Identity keys, known Destination hashes, known Packet bytes, known announce data — generated by the Python RNS. Verify the Crystal implementation produces byte-identical outputs for the same inputs. Focus on: hash computation, packet encoding, announce format, ECDH key exchange, Token encrypt/decrypt. This is critical — the Crystal port must be wire-compatible with the Python implementation.

- [ ] **12.2 — Run ameba linter and fix all issues**
  Run `crystal tool format` on all source files. Run `ameba` linter. Fix all warnings and errors. Ensure consistent code style throughout. Review all `# TODO` and `# FIXME` comments and resolve them.

- [ ] **12.3 — Performance benchmarking**
  Create `benchmarks/` directory. Write benchmarks for: crypto operations (encrypt/decrypt throughput, sign/verify throughput, hash throughput), packet encoding/decoding, link establishment time, resource transfer throughput. Compare against Python RNS performance where possible. Optimize any hot paths that are slower than expected.

- [ ] **12.4 — Final review and shard release preparation**
  Review all public API documentation (Crystal doc comments). Ensure `shard.yml` metadata is complete (description, license, repository URL). Verify `crystal docs` generates complete API documentation. Test `shards build` produces all binary targets. Create a README.md in `` with: installation instructions, quick start guide, API overview, link to examples. Verify all specs pass with `crystal spec`. Tag version 0.1.0.
