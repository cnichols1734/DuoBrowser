# Security policy

## Report privately

Email **chrisnichols17@gmail.com** with the subject **DuoBrowser security report**. Do not open a public issue, Discussion or pull request containing an exploitable vulnerability.

After public launch, GitHub's [Report a vulnerability](https://github.com/cnichols1734/DuoBrowser/security/advisories/new) form is an additional option if enabled. If the form is unavailable, use email. Do not assume GitHub private reporting is enabled while the repository is private.

Include affected commit/version, impact, reproducible steps and a minimal synthetic proof of concept. Do not send passwords, session cookies, private keys, real browsing history or another person's information. Ask for a suitable secure transfer method before sending sensitive evidence. Ordinary email is not an end-to-end encrypted channel.

The maintainer aims to acknowledge reports within seven days and coordinate remediation and disclosure with the reporter. This is a volunteer project, not a paid response SLA or bug bounty. Test only your own accounts/devices, avoid disruption and do not access other users' data.

## Supported versions and boundaries

DuoBrowser is pre-release. Security fixes target the current `main` branch; older experimental commits are not supported release lines. A supported-version table will be added with the first release.

The app has no analytics, advertising SDKs, tracking service or app backend. Requests still reach the sites you visit and your chosen navigation/search destinations. Website tracking and network observation are outside the meaning of "no app tracking."

Normal browsing uses persistent WebKit storage. Private tabs use a separate nonpersistent store; explicitly saved bookmarks and Files exports persist by user choice. Private mode does not provide anonymity. Camera avoidance is local, bounded and reversible; no page content is sent to an AI service.

Code signing and App Store publication stay outside community CI. Never commit credentials or provisioning material. If a credential reaches Git history, revoke/rotate it first, then coordinate history cleanup; deleting the latest file is insufficient.
