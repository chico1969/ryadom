# SignPath Foundation application worksheet

Draft only. Do not submit until all `TO_FILL` fields and prerequisites are
resolved. Do not invent users, contributors, reviews or public reputation.

| Field | Proposed answer |
| --- | --- |
| Project name | Ryadom (Рядом) |
| Repository | https://github.com/chico1969/ryadom (public fork, default branch ryadom) |
| Homepage | https://github.com/chico1969/ryadom |
| Download page | https://github.com/chico1969/ryadom/releases/tag/ryadom-test-2026-11-16 (unsigned test release) |
| License | GNU AGPL version 3; upstream notices retained |
| Privacy policy | https://github.com/chico1969/ryadom/blob/ryadom/PRIVACY.md |
| Code signing policy | https://github.com/chico1969/ryadom/blob/ryadom/CODE_SIGNING.md |
| Maintainer / contact | chico1969; TO_FILL: application email and any required legal/contact name |
| Committers and reviewers | https://github.com/chico1969 ; initially one maintainer |
| Release approver | chico1969; TO_FILL: confirmed SignPath identity; manual approvals |
| Proposed signing build system | GitHub Actions, exclusively GitHub-hosted Windows/Linux runners |
| Target | Windows 10/11 x64; portable executable and service installer |

## Short description (ready to paste)

Ryadom is an independent AGPL-3.0 remote assistance fork of RustDesk 1.5.3 for
Windows 10 and 11. It provides a Russian interface for personal assistance to
family and known users, including a portable application and an installed
Windows service. Connections require user approval or configured
authentication. WebRTC is used for the session transport, with direct P2P and
an optional user-configured TURN fallback. It is not an official RustDesk build.

## Provenance and fork disclosure

Upstream source: https://github.com/rustdesk/rustdesk
Upstream release: https://github.com/rustdesk/rustdesk/releases/tag/1.5.3
Pinned base commit: 95cca3f661f635b3cc85c04935fe8d96d8f432ef

The public fork and Ryadom development sources are published. The official upstream Windows
x64 1.5.3 download was checked locally with Windows Authenticode on 15 November
2026: valid signature, publisher `PURSLANE`, timestamp present, SHA256
`523ba0efbf62a21739961b62c7daaffb44d3da86139c546b364fd4e1333ed249`.
This is evidence for the signed-upstream condition, not approval of our fork.
All changes, dependency patches, generated bridge provenance and build scripts
will be available for review. Third-party binaries will not be signed under our
project's identity. Proprietary runtime components are not intentionally part
of the Flutter build; a complete packaged dependency/license review is still
required.

License-grant documentation is unresolved for the pinned
`flutter_gpu_texture_renderer`, `default_net`, `impersonate_system` and
the separate `hbb_common` submodule. These need authoritative clarification; this worksheet does not
assign a license to them. A partial `ryadom/THIRD_PARTY_NOTICES.txt` has been
added to source for AOM, libvpx, libyuv and Opus. Its inclusion in the next
packaged build and the remaining Rust/native notices still need validation.

Clarification requests: [GPU renderer](https://github.com/rustdesk-org/flutter_gpu_texture_renderer/issues/5)
and [default_net](https://github.com/rustdesk-org/default_net/issues/6).
The `impersonate-system` repository has issues disabled, so its question was
[posted in RustDesk](https://github.com/rustdesk/rustdesk/issues/17080).
The `hbb_common` license declaration at `fae47e024dd83cef6aaecde0aa7d11731df11649`
also needs clarification; the existing
[upstream discussion](https://github.com/rustdesk/rustdesk/discussions/15801)
is unanswered. Missing declarations do not prove the absence of rights, and
unanswered requests are not license grants.

## Current reputation and testing (honest disclosure)

This is a new project in development, currently tested by the owner and family
on two Windows computers. There is no established independent public user base,
external review history or community adoption evidence to claim yet. Local
installer, update, service and autostart checks have passed. Full cross-network,
long-duration and reboot acceptance testing remains in progress. We understand
that the Foundation may decline a new project without verifiable public
reputation and that a signature is not a security endorsement.

An unsigned public test release is available at the download URL above.
GitHub-hosted [run 43757455942](https://github.com/chico1969/ryadom/actions/runs/43757455942)
succeeded without signing at revision `512671e`. That earlier run is not
evidence that the current installer privacy changes or native notices have
built and passed packaged validation. A fresh hosted build is required for the
candidate submitted for signing.

## Signing design / questions for reviewer

The app uses a custom Brotli portable package. We propose two requests per build:
first sign our inner launcher/core DLL, then package those returned files and
sign the two outer executables. Both stages enforce product name `Рядом` and the
same four-part version. No arbitrary local binaries are submitted. Every
request must receive manual production approval. Please confirm this layout,
the fork's eligibility and whether the initial single-maintainer role assignment
is acceptable before enabling production signing.

Family TURN account credentials and hosting/signing private keys will not be
published or injected into the public signing build. The Windows installer
source now displays its own local Russian privacy disclosure and a separate
background-network choice, preserving the host's current choice on updates.
Disabling it stops incoming background registration after installation;
explicit outgoing connections and re-enabling incoming access may use the
network again. Autostart remains independent. Packaged Windows validation and
maintainer review are still required before a public signed release.

## Submission

Official form: https://signpath.org/apply
Requirements: https://signpath.org/terms

The owner supplies personal/contact data and accepts program terms. No
application has been sent by preparing this file. Do not add the sponsorship
acknowledgement as an active claim until accepted and production signing works.
