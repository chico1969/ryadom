# SignPath Foundation application worksheet

Draft only. Do not submit until all `TO_FILL` fields and prerequisites are
resolved. Do not invent users, contributors, reviews or public reputation.

| Field | Proposed answer |
| --- | --- |
| Project name | Ryadom (Рядом) |
| Repository | https://github.com/chico1969/ryadom (created; Ryadom changes being prepared for publication) |
| Homepage | https://github.com/chico1969/ryadom (after source publication) |
| Download page | TO_FILL: actual development release URL |
| License | GNU AGPL version 3; upstream notices retained |
| Privacy policy | PRIVACY.md in the public fork; copy its actual URL after publication |
| Code signing policy | CODE_SIGNING.md in the public fork; copy its actual URL after publication |
| Maintainer / contact | chico1969; TO_FILL: application email and any required legal/contact name |
| Committers and reviewers | https://github.com/chico1969 ; initially one maintainer |
| Release approver | chico1969; TO_FILL: confirmed SignPath identity; manual approvals |
| Build system | GitHub Actions, exclusively GitHub-hosted Windows/Linux runners |
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

The public fork has been created. Our current local Ryadom changes have not yet
been published to it. The official upstream Windows
x64 1.5.3 download was checked locally with Windows Authenticode on 15 November
2026: valid signature, publisher `PURSLANE`, timestamp present, SHA256
`523ba0efbf62a21739961b62c7daaffb44d3da86139c546b364fd4e1333ed249`.
This is evidence for the signed-upstream condition, not approval of our fork.
All changes, dependency patches, generated bridge provenance and build scripts
will be available for review. Third-party binaries will not be signed under our
project's identity. Proprietary runtime components are not intentionally part
of the Flutter build; a complete packaged dependency/license review is still
required.

## Current reputation and testing (honest disclosure)

This is a new project in development, currently tested by the owner and family
on two Windows computers. There is no established independent public user base,
external review history or community adoption evidence to claim yet. Local
installer, update, service and autostart checks have passed. Full cross-network,
long-duration and reboot acceptance testing remains in progress. We understand
that the Foundation may decline a new project without verifiable public
reputation and that a signature is not a security endorsement.

## Signing design / questions for reviewer

The app uses a custom Brotli portable package. We propose two requests per build:
first sign our inner launcher/core DLL, then package those returned files and
sign the two outer executables. Both stages enforce product name `Рядом` and the
same four-part version. No arbitrary local binaries are submitted. Every
request must receive manual production approval. Please confirm this layout,
the fork's eligibility and whether the initial single-maintainer role assignment
is acceptable before enabling production signing.

Family TURN account credentials and hosting/signing private keys will not be
published or injected into the public signing build. The privacy disclosure and
the installer's network opt-out must be reviewed before a public signed release.

## Submission

Official form: https://signpath.org/apply
Requirements: https://signpath.org/terms

The owner supplies personal/contact data and accepts program terms. No
application has been sent by preparing this file. Do not add the sponsorship
acknowledgement as an active claim until accepted and production signing works.
