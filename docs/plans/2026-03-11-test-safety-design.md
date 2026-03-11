# Test Safety: Network Test Isolation and Teardown

## Problem

Running `crystal spec` executes heavy networking tests (multicast, stress tests, multi-socket UDP/TCP) that can overwhelm macOS's `configd` daemon, causing system-wide network degradation and kernel panics.

## Design

### 1. Tag-Based Test Filtering (Safe by Default)

Add a guard to `spec_helper.cr` that skips tagged tests when no tags are requested on the command line.

```crystal
class Spec::CLI
  def tags
    @tags
  end
end

Spec.around_each do |example|
  tags = Spec.cli.tags
  next if (tags.nil? || tags.empty?) && !example.example.all_tags.empty?
  example.run
end
```

Behavior:
- `crystal spec` -- runs only untagged (unit) tests
- `crystal spec --tag network` -- runs only network-tagged tests

### 2. Tagged Describe Blocks

The following describe blocks receive `tags: "network"`:

**udp_interface_spec.cr:**
- `"stress tests"` -- 50 rapid sends, 20 send/receive cycles

**multi_interface_spec.cr:**
- `"UDP interface send/receive between two interfaces"` -- 2-4 UDP socket pairs
- `"TCP LocalInterface client-server communication"` -- TCP server/client
- `"Stress tests"` -- 20 interfaces with 50 paths

### 3. Global Interface Cleanup

Add `after_each` to `spec_helper.cr` that tears down any interface still online and resets Transport state, as a safety net for leaked resources.

### 4. Consistent Teardown in Tests

- Wrap all socket-owning tests in `begin/ensure` blocks
- Call `teardown` (not just `detach`) on every interface
- The global `after_each` catches anything tests miss

## Files Changed

| File | Change |
|------|--------|
| `spec/spec_helper.cr` | Tag filter, global after_each, skip notice |
| `spec/rns/interfaces/udp_interface_spec.cr` | Tag stress tests |
| `spec/rns/integration/multi_interface_spec.cr` | Tag network tests, fix teardown |
