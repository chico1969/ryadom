# Ryadom / «Рядом»: privacy and network information

Status: development policy, 16 November 2026. This describes the current source
and proposed public signing build. It must be reviewed by the project owner
before publication. It is not a claim of legal certification.

## Purpose and access

Ryadom is a Windows remote assistance application based on RustDesk. The remote
computer must approve access or authenticate a previously configured access
method. Its ID is a lookup address, not permission to control the computer.
Screen, sound, input, clipboard, files, chat and terminal data are exchanged only
as part of the features used in an authorized session. A recording is stored
locally by the participant who starts recording; it can contain personal data.

## External network services

The application contacts its configured signaling service automatically while
accepting or starting connections. The currently configured public endpoint is
`wss://ryadom-family.alwaysdata.net/peerjs`, hosted at alwaysdata. The service can
see the connection's public IP address, lookup IDs, device public keys, session
negotiation messages, timestamps and WebRTC network candidates. Candidates may
contain local and public IP addresses and ports. The server is not a transport
for desktop, clipboard, files or terminal commands. Network/session metadata
may also appear in the host's operational logs. We do not promise zero logging
by the hosting provider.

STUN servers receive network requests that help discover a direct route. TURN,
if configured and used, relays encrypted session traffic and sees endpoint IP
addresses, timing and traffic volume. Private family builds currently use an
owner-configured ExpressTURN account. This account's credentials are not part
of the proposed public signing build. Owners may configure their own TURN
service. Direct P2P does not consume TURN relay traffic, but signaling and STUN
still exchange small network messages.

Third-party policies:

- alwaysdata data protection notice: <https://www.alwaysdata.com/en/terms-and-legal/>
- ExpressTURN: <https://www.expressturn.com/> (review the provider's current
  privacy/terms pages before publishing a build with this service).
- Configured STUN/TURN providers can differ between deployments; consult the
  configuration and the provider's policy. No country-wide availability is
  guaranteed.

The P2P helper, when enabled, contacts the local router to request a temporary
UDP mapping, renews that mapping, and may ask for administrator permission to
create the application's Windows firewall rule. The helper is optional.

## Local data and removal

Windows stores application settings, identity, access configuration, saved
computers, connection history and diagnostic logs locally. Stored secrets are
protected using the mechanisms described in the project's security document;
an authorized operating-system administrator can still access the computer.
The browser version uses browser storage for its local settings. The project
does not provide cloud address-book synchronization, application accounts,
advertising or a separate analytics service.

The Windows installer includes a readable Russian disclosure and a separate
"Allow background connections for incoming access" choice. It preserves the
host's existing choice when updating. If disabled, the installed app does not
register this PC for incoming connections in the background. An explicitly
started outgoing connection or enabling incoming access can use the network
again. Windows autostart is a separate choice; disabling autostart does not
terminate running connections. Older downloaded builds do not gain this
installer choice without an update.

Disable incoming access and close outgoing sessions to stop background access.
Uninstall the Windows service to stop unattended access. Removing
the app does not necessarily remove saved user configuration; remove the
Ryadom profile data separately if you intend to erase the device's identity
and access settings. Clear site storage to remove browser settings. Remove
recordings and downloaded files separately.

## Before a public signed release

The maintainer must publish a contact method, review provider-policy links,
verify all packaged dependencies' licenses, and validate the new installer's
disclosure and background-network choice in the packaged Windows build. The
installer displays its own policy text locally and links to this full policy.
Source implementation and tests do not assert SignPath approval or replace the
maintainer's privacy and runtime review.

For now, report security/privacy issues privately to the repository owner after
the official repository and contact method have been named. Do not post access
passwords, device private keys or personal logs in a public issue.
