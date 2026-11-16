# Code signing policy

## Current status

The owner submitted Ryadom (Рядом) to the SignPath Foundation Open Source
program on 16 November 2026; the web form confirmed receipt. The application
has not been approved. Current development downloads
are unsigned. No SignPath sponsorship or trusted publisher status is claimed.

Project license: [GNU AGPL version 3](LICENCE).
Upstream: [RustDesk](https://github.com/rustdesk/rustdesk), version 1.5.3,
commit `95cca3f661f635b3cc85c04935fe8d96d8f432ef`.
This is an independent fork, not an official RustDesk release.

## Repository and roles

The public repository is <https://github.com/chico1969/ryadom>, created as a
visible fork. Ryadom development sources are published on its `ryadom` branch.
The [public test release](https://github.com/chico1969/ryadom/releases/tag/ryadom-test-2026-11-16)
is unsigned. An earlier [unsigned hosted build](https://github.com/chico1969/ryadom/actions/runs/43757455942)
succeeded at revision `512671e`; it does not validate the current candidate's
installer privacy changes or added native notices. A fresh hosted build and
packaged validation are still required.
See [the application worksheet](ryadom/signing/APPLICATION.md).
The upstream Git remote is not the destination for Ryadom releases.

Project owner [chico1969](https://github.com/chico1969) will be the committer,
reviewer and release approver for the initial single-maintainer project.
The owner must separately confirm the SignPath identity and enable MFA.
Contributors and automated tools cannot
approve production signing requests. All users with repository write access or
SignPath access must enable multi-factor authentication. Application changes,
dependency patches and build/workflow changes require maintainer review before
a release is submitted for signing.

## Eligible artifacts and release process

Only binaries built from the public Ryadom source revision on GitHub-hosted
runners may be submitted. Downloaded local development builds and arbitrary
uploaded executables are not signing inputs. Existing RustDesk and third-party
library binaries must not be signed under the project's identity.

The proposed workflow is `ryadom-signpath.yml`. It is manually started, disabled
until configured, and never runs signing for pull requests. It requires a
protected `signpath-release` GitHub environment and manual approval in SignPath
for each production request. Its enabled state is not proof that a release has
been certified.

Signing has two stages because Ryadom uses its own compressed portable package:

1. Sign the project's inner Windows launcher `Ryadom.exe` and native core
   `librustdesk.dll`. Enforce product name `Рядом` and one numeric four-part
   version on both. Include upstream libraries unchanged and do not sign them
   using the project's certificate.
2. Verify the returned signatures, package these exact signed files, then sign
   the outer `Ryadom.exe` and `Ryadom-Setup.exe`. Verify the signatures and hashes
   again. Do not change signed files after this point.

The maintainer must approve both requests. The workflow uploads artifacts for
review; it does not automatically publish a GitHub Release. A release must
include corresponding sources, AGPL notices and checksums. Artifact signing
does not replace runtime/security testing or guarantee removal of SmartScreen
warnings.

## Secrets and privacy

The signing token is stored only in the protected GitHub environment. It must
have submitter permissions only; approvals are performed separately by the
maintainer. Tokens, private keys, hosting credentials, personal device settings
and the family's shared TURN credentials must not enter the public repository
or public signing builds. The public workflow builds without bundled TURN
credentials. Existing private family builds remain separate and unsigned.

See [Privacy policy](PRIVACY.md) for network services and local data.
The Windows installer source includes its own local privacy disclosure and an
independent choice to disable background registration for incoming access.
Windows autostart and explicitly started outgoing connections are separate.
The packaged installer and this behavior must be validated and reviewed before
production signing; their implementation does not imply SignPath approval.

License-grant documentation remains unresolved for the pinned
`flutter_gpu_texture_renderer`, `default_net`, `impersonate_system` and
the separate `hbb_common` submodule. The new [native notices](ryadom/THIRD_PARTY_NOTICES.txt) cover
AOM, libvpx, libyuv and Opus; they are a partial inventory. Their inclusion in
the next packaged build and the remaining Rust/native notices still need
validation. These documents do not assign missing licenses or certify that
the dependency review is complete.

## Attribution after approval

Only after SignPath has accepted the project and a production signature has
been verified, add the following acknowledgement to this page and the download
page:

> Free code signing provided by [SignPath.io](https://about.signpath.io/),
> certificate by [SignPath Foundation](https://signpath.org/).

This is the required future acknowledgement, not a statement of current support.

Requirements: <https://signpath.org/terms>.
