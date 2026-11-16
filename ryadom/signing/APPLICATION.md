# SignPath Foundation application worksheet

The owner submitted the official form on 16 November 2026, and the website
confirmed receipt. Approval is pending. The license and fresh-candidate validation
questions below remain open; submission is not a claim that they are resolved.
Keep the owner's personal contact details out of this public worksheet.
GitHub MFA has been confirmed. SignPath identity, MFA and signing permissions
remain to be configured once the SignPath account is provided, before
production signing. Do not invent users, contributors, reviews or public reputation.

| Field | Proposed answer |
| --- | --- |
| Project name | Ryadom (Рядом) |
| Repository | https://github.com/chico1969/ryadom (public fork, default branch ryadom) |
| Homepage | https://github.com/chico1969/ryadom |
| Download page | https://github.com/chico1969/ryadom/releases/tag/ryadom-test-2026-11-16 (unsigned test release) |
| License | GNU AGPL version 3; upstream notices retained |
| Privacy policy | https://github.com/chico1969/ryadom/blob/ryadom/PRIVACY.md |
| Code signing policy | https://github.com/chico1969/ryadom/blob/ryadom/CODE_SIGNING.md |
| Maintainer / contact | chico1969; owner supplies the required name and application email directly in the official form |
| Committers and reviewers | https://github.com/chico1969 ; initially one maintainer |
| Release approver | chico1969; GitHub MFA confirmed, SignPath identity/MFA and approval role pending account provision |
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
added for AOM, libvpx, libyuv and Opus and was present in the inspected 0.1.0.2
packages. The remaining Rust/native notices still need review.

Clarification requests: [GPU renderer](https://github.com/rustdesk-org/flutter_gpu_texture_renderer/issues/5)
and [default_net](https://github.com/rustdesk-org/default_net/issues/6).
The `impersonate-system` repository has issues disabled, so its question was
[posted in RustDesk](https://github.com/rustdesk/rustdesk/issues/17080). That
endpoint later returned HTTP 410 with the message "This issue was deleted";
the question is no longer available there.
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
Official GitHub-hosted [run 43876303443](https://github.com/chico1969/ryadom/actions/runs/43876303443)
succeeded without signing for version 0.1.0.2 at revision
`e7cdddea1e95d294fcc82c71498e83fd4545bd9c`. Four installation policy/autostart
scenarios and a separate service restart passed their checks. The harness later
failed during restoration; a separate recovery restored the original profiles
and service. This is not reported as an entirely successful harness run.

A local footer layout fix using the same hosted native core was then installed
once; all 93 installed runtime files matched that candidate, including the
native notices. The four scenarios were not repeated with the new UI.
The fresh [unsigned 0.1.0.3 run 43913604981](https://github.com/chico1969/ryadom/actions/runs/43913604981)
at revision `51321dd01e466054af24a994b2f81fb440c01134` was started.
Its completed artifacts and installation are not yet verified, and none of
these checks is a signing approval.

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
network again. Autostart remains independent. The completed packaged checks
above concern 0.1.0.2 and one local UI-fix installation; the fresh 0.1.0.3
package and maintainer review are still required before a public signed release.

## Submission

Official form: https://signpath.org/apply
Requirements: https://signpath.org/terms

The owner entered personal/contact data and submitted the official web form.
This worksheet records preparation and remaining questions; it is not an
approval from SignPath. Do not add the sponsorship acknowledgement as an
active claim until accepted and production signing works.
