# Owner-controlled releases

Only Christopher Nichols (`@cnichols1734`) may authorize an official release or App Store submission. A merged pull request is not release authorization. There is no automatic publishing workflow and no signing material in GitHub Actions.

## From contribution to release

1. A contributor opens a PR. CI compiles Swift, runs unit/layout/native checks, lints sources and verifies repository/dependency hygiene.
2. The owner reviews scope, code, security and evidence. Protected-branch requirements must pass. No PR is guaranteed acceptance.
3. The owner merges the reviewed PR. Multiple changes can accumulate on `main` without producing a release.
4. The owner explicitly chooses a version and an approved commit. Record the exact SHA, change notes and known limitations. Rerun CI on that commit; verify that no later changes entered the release build.
5. On a trusted, owner-controlled Mac, perform physical-device checks: credentials/passkeys with correct entitlements, private-session behavior, uploads/downloads, permission prompts, media, accessibility, folding, memory/energy and network transitions. Review the existing release gates in `docs/PRODUCTION_IMPLEMENTATION_2026-10-27.md`.
6. Review all source and dependencies before opening/building them with signing credentials available. Set the final bundle ID and development team locally. Select the approved version/build number, archive a Release build, and inspect entitlements, privacy declarations, third-party notices and signing. Keep profiles, certificates, `.p8` keys, export options and provisioning details outside Git.
7. The owner explicitly authorizes App Store Connect upload/submission as a separate action. A tag, CI success or PR approval does not grant that authorization. TestFlight distribution also requires owner authorization.
8. Only after authorization, publish the appropriate Git tag/release notes and perform the approved distribution steps. Preserve the source SHA and archive provenance. Do not silently replace an existing release tag.

## Protection and review edge cases

Every change must go through a PR with passing, up-to-date CI and resolved conversations. Force pushes and branch deletion remain blocked, including for the owner. A separate review ruleset requires approval and code-owner review, dismisses stale approvals, and requires approval after the latest push. Its only bypass actor is Christopher Nichols (`@cnichols1734`), and the bypass works only through PRs. He may merge his own PRs without another reviewer or make the final review decision on community PRs. This exception does not bypass the separate CI/PR/integrity protections and does not authorize anyone else to merge or publish releases.

GitHub may present the review exception as a bypass confirmation in the merge UI. The owner can use it after the mandatory checks pass. Automation must not weaken protection, add bypass actors or assume that owner bypass privileges authorize a merge; explicit owner authorization is still required for agent-initiated merges and releases.

Repository administrators can change settings; GitHub configuration cannot remove the owner's ultimate administrative authority. Outside contributors receive no repository write/admin rights or release credentials. Keep auto-merge disabled, including for Dependabot. See `docs/OPEN_SOURCE_PREPARATION.md` for verified settings and any plan/API limitations.

## Before public visibility

Merge the preparation PR only after its review requirements are satisfied. Obtain an explicit owner instruction to make this repository public. Recheck historical personal metadata, licensing, documentation, CI, private disclosure and protections. After the separately approved visibility change, verify anonymous access and immediately recheck protection, secret scanning, push protection, Dependabot, fork workflow approval and private vulnerability reporting. Do not publish an App Store build as part of changing visibility.
