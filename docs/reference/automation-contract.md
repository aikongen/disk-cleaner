---
audience: consumer
---

# Automation contract

Use this page when an agent or script needs to request available disk space through `disk-cleanerctl`. It describes the current implementation, not a stable public protocol. The only current automation transport is a same-user command-line executable. There is no MCP server, HTTP API, daemon or completion-event subscription. Requests never accept deletion paths, commands or policy. No cleanup provider is enabled.

## Commands and effects

| Command | Result and effects |
| --- | --- |
| `disk-cleanerctl request <target-available-bytes> <idempotency-key>` | Persist a queued job before acknowledging it; launch the same executable as a child capacity-check worker; emit the acknowledged job as one JSON line. The worker may already have finished when the caller reads this queued acknowledgement. |
| `disk-cleanerctl status <job-id>` | Emit the saved job. A still-queued request older than 60 seconds is conservatively changed to `interrupted` during retrieval; the worker cannot subsequently execute that interrupted job. |
| `disk-cleanerctl wait <job-id>` | Poll the saved job every 200 ms while queued/running, then emit the terminal job. No caller-configurable timeout or cancellation contract is implemented. |
| `worker <job-id>` | Internal child-process entry point; not the client API. It is not a security boundary against another process running as the same user. |
| `fixture-capability` | DEBUG-only test preflight; emits `disk-cleaner-debug-fixture-v1` as plain text without resolving a state directory. It is not available in release builds. |

The target is a **positive Int64 count of available bytes**, not “bytes to remove.” The key is nonempty and at most 256 UTF-8 bytes. Replaying the same key and target returns the same job ID. Reusing the key with a different target fails. Retain the key and job ID across disconnects; a new logical request needs a new key. Terminal jobs are not rerun on replay. Repeated queued requests can launch extra workers, but the cross-process ledger lock and queued-state guard serialize the existing no-provider capacity check.

The current capacity check uses `/`, the startup/root filesystem; clients cannot choose another volume. A normal folder scan's volume is not implicitly the CLI target. No low-space threshold is built into this interface.

## Example syntax

These commands match the current argument parser. Requests write real product state when used with a normal binary, so run them only when you mean to. Do not use a preview app's bundled CLI to assume fixture isolation.

```sh
# Use the normal app's embedded helper.
cli="$DISK_CLEANER_APP/Contents/MacOS/disk-cleanerctl"  # path to Disk Cleaner Visual Repair.app, for example .../delivery-06/Disk Cleaner.app
"$cli" request 24000000000 'my-work-unique-request-key'
# Read the returned id, then substitute that UUID below.
"$cli" status '<job-id>'
"$cli" wait '<job-id>'
```

A process exit of **0 means the command returned a job successfully**, including a job whose status is `insufficient`, `failed` or `interrupted`. It does not mean the capacity goal was met. Decode `status`, inspect the target/measurements and act on the result. Exit 1 indicates argument, lookup, persistence, idempotency, worker-launch or other command failure; stderr contains one JSON object with an `error` string. Error messages are human descriptions, not versioned machine error codes.

## JSON fields

Job output is sorted-key JSON followed by a newline. Dates are ISO 8601 strings. Optional measurements may be absent; absence is not zero. `Int64` quantities can exceed JavaScript's exact-number range; preserve integer precision when decoding. There is no wire-schema version or compatibility negotiation yet.

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | UUID string | Stable persisted job identity. |
| `key` | string | Client idempotency key. |
| `targetBytes` | Int64 | Requested available-capacity target. |
| `status` | string | State below. |
| `createdAt` | ISO 8601 string | Creation time; no separate completion time is recorded. |
| `beforeBytes`, `afterBytes` | optional Int64 | Observed available capacity; not deleted file bytes. |
| `message` | string | Human explanation, not a stable machine error code. |
| `requester` | string | `agent` for CLI enqueue; other callers may supply their own name through the library. |

| Status | Current interpretation |
| --- | --- |
| `queued` | Persisted; waiting for worker. |
| `running` | Defined in the model; the current no-provider worker does not persist this intermediate state. |
| `completed` | Available capacity already met the target; no cleanup performed. `beforeBytes == afterBytes` for this worker. |
| `insufficient` | Target unmet; no cleanup rule enabled. |
| `failed` | Worker/capacity failure; inspect measurements and message. A command-level failure can instead return exit 1 without a job line. |
| `interrupted` | Stale queued work was reconciled conservatively; result unknown. Never infer success or retry destructive work. |

Capacity is volatile after any measurement. Resume the original work only when the current result supports sufficient space; handle a subsequent capacity failure honestly. Never broaden cleanup policy to force a successful result.

## Durability, isolation and limits

Normal state is `~/Library/Application Support/DiskCleaner/jobs.json`. The ledger uses shared/exclusive process locks, atomic file replacement and file/directory fsync. A write failure cannot return successful acceptance. Corrupt JSON fails without replacement. These mechanisms and fixtures are useful evidence, not a proof of power-loss or actual ENOSPC resilience.

No history retention/byte budget, schema migration, event delivery, cancellation endpoint, operation deadline or full-disk reserve is implemented. Do not silently add one while treating it as a documented current capability. No transport rewrite is necessary simply because polling is the present contract.

DEBUG CLI fixtures require both `DISK_CLEANER_FIXTURE_MODE=1` and an absolute `DISK_CLEANER_FIXTURE_DIR` containing `.disk-cleaner-fixture`. The capability preflight must succeed before fixture use. Release builds ignore these variables and resolve normal Application Support. The shipped preview app's visual demo flag does not alter CLI behavior. Existing integration tests intentionally use the same-build DEBUG helper and temporary directories.

Maintainer source: [`Sources/DiskCleanerCLI/main.swift`](../../Sources/DiskCleanerCLI/main.swift) and `Sources/DiskCleanerCore/{Models,Jobs,Persistence}.swift`; the fixture test `cliRequestsReplayAndStatusInAnIsolatedFixture` in [`CLIIntegrationTests.swift`](../../Tests/DiskCleanerCoreTests/CLIIntegrationTests.swift) exercises the request, replay and status path.
