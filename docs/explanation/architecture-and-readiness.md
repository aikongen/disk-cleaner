---
audience: maintainer
---

# Architecture and quality path

Use this page to see how Disk Cleaner's parts fit together and what has to improve, in order, before it is more than a personal inspection tool.

Disk Cleaner has sensible initial boundaries: SwiftUI/AppKit and the CLI are separate consumers of a shared Core library. Inventory is discovery; it never grants cleanup eligibility. Jobs accept a space goal and own the outcome. This does not need a broad rewrite to become useful.

The current implementation is an early personal inspection and capacity-check tool. It is not yet the unattended cleaner described by the intended workflow, and its ad-hoc signed development builds are not a public release.

```text
Human → SwiftUI/App model ─┐
                          ├→ Core → inventory snapshots / job JSON ledgers
Agent → CLI → own worker ──┘              ↑ process locks + atomic writes
                                         no cleanup provider
```

## Smallest useful order

1. Give the source an explicit development version identity now that it lives in this repository, and finish the operator and client handover using the guides now present.
2. Make personal inspection complete enough to trust. Browsing the saved scan without rescanning, with breadcrumbs and back, is in place; retaining root and history context, exposing reachable coverage gaps and handling realistic scan sizes are planned and still to be assessed. Validate bounded resource usage and failure behavior on synthetic fixtures.
3. Bound and recover storage: choose job-history retention without losing live idempotency, add supported ledger-version handling and backup/recovery behavior, and prove disk-full/crash outcomes. Keep process safety and conservative unknown results.
4. Implement the first explicitly approved cleanup category only after matched-version macOS safety evidence. Category approval is still absent. Prove exclusion with relevant clients, interruption, regeneration consequences and measured outcomes. No automatic category approval follows from improving docs or appearance.
5. Harden the existing CLI as a consumer contract: versioned schema/errors, client deadlines/reconnect behavior and compatibility fixtures. Keep polling if it solves the need; do not mandate MCP, a daemon or an event bus.
6. If public distribution becomes the goal, choose its audience/channel and complete release identity, supported OS/hardware testing, signing/notarization, privacy/permissions, packaging/update/recovery/support. Public accessibility validation then becomes applicable under the product rule. These are separate from achieving good personal-use behavior first.

These are an assessed quality path, not an approved implementation schedule or authority to publish. Fixing a missing capability is different from making every internal type reusable or splitting the UI file.
