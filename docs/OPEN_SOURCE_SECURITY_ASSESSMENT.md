# Pre-publication security assessment

Reviewed October 27, 2026, before implementation of the open-source transition. Baseline: `f168f4d`. This is a repository-exposure assessment, not a penetration test or proof of browser security.

## Scope and findings

| Area | Evidence | Assessment |
| --- | --- | --- |
| Committed secrets | Gitleaks 8.30.1, default rules, full `--all` history, fully redacted reports; 17 reachable commits and 141 unique blobs inspected | No secret findings. No committed key, certificate, provisioning profile, environment file or signing configuration found. No credential rotation indicated by this scan. |
| Local ignored files | Local directory scan, 10 MiB per-file scan ceiling; 92 ignored files inventoried | One private-key finding: the ignored loopback TLS fixture key in `work/`. Its self-signed certificate tests rejection; neither file occurs in Git history. Do not publish scratch directories. Binary/build content was inventoried, not semantically audited. |
| Personal metadata | All reachable blobs and commit author/committer metadata | Historical author email, a local workspace path and simulator identifiers are present. Remove machine-specific paths/identifiers from current instructions; history remains a separate publication decision. Do not describe a current-file cleanup as history removal. |
| Signing | Xcode project build settings and tracked-file/history inventory | Generic `dev.local.DuoBrowser` bundle ID; automatic signing style, no development team, no managed entitlements, profiles, signing certificates or App Store keys. Physical signing is owner-local work. |
| Dependencies | Imports, project references and all historical manifests | Apple system frameworks only at runtime. No SPM, CocoaPods, Carthage, vendored library or JavaScript runtime package. Existing JS regression tests use external Playwright tooling, not shipped code. Apple SDKs remain under Apple's terms; they are not relicensed. |
| Artwork rights | Current icon and prior asset history | Owner-supplied image, subsequently edited with built-in image tooling; third-party provenance is not independently established. Confirm rights before including it under MIT. Historical generated icon concepts are also present. |
| Actions | Repository API and tracked workflow inventory | No existing workflows, Actions secrets, environments, webhooks or deploy keys. Actions currently allow all actions; token default is read-only and workflow PR approval is disabled. Harden before community PRs. |
| Access | Collaborator and branch-protection APIs | Only owner `cnichols1734` has access (admin). `main` is unprotected. Auto-merge is already disabled. Dependabot alerts are initially disabled. |
| Size and artifacts | All Git blobs, including historical deleted versions | Only binary path is the app icon; largest historical blob is 967,192 bytes. No tracked simulator data, recordings, build products or large archives. |

## Assessment and required follow-up

Preparation can proceed while the repository stays private. Publication is gated on explicit owner approval, the historical metadata decision, verified artwork licensing, a usable private reporting contact, and final CI/protection verification. No history rewrite, credential rotation, public visibility change or new collaborator access is part of the audit.

The next changes add MIT licensing for project-owned work, contributor/security documentation, safe CI, issue templates and owner-controlled governance. Existing browser behavior must remain unchanged. Newly introduced tooling and licenses must be recorded in `THIRD_PARTY_NOTICES.md`.

Raw scan reports and tooling live only in ignored `work/open-source-audit/`; secret values are redacted. Scanners can miss unknown credentials and non-text secrets. The 10 MiB ceiling applies to local ignored-file scanning; every tracked historical blob is smaller than 1 MiB. Remote repository contents, not the local ignored files, are the publication boundary.

## Owner decisions after the assessment

The owner approved the existing author email as the public private-reporting contact and confirmed the right to license the icon under MIT. On being asked for a recommendation about history, the recommendation was to preserve it: the retained local paths and simulator IDs are not credentials, and rewriting a clean history would disrupt references without removing a discovered secret. Current instructions remove those machine-specific details. Historical metadata exposure remains disclosed for the final visibility decision; no force push or history rewrite occurred.
