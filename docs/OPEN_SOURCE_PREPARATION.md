# Open-source preparation status

Pre-publication snapshot, October 27, 2026. Repository: `cnichols1734/DuoBrowser`. Preparation branch: `chore/open-source-preparation`. The repository was private when the settings below were audited. This document records preparation-time findings, not live repository status. No App Store publication is authorized or configured.

The owner subsequently approved public visibility and merging PR #1. He then replaced the proposed one-time exception with an explicit permanent owner-only review exception: the `Main review - owner final authority` ruleset names only user `cnichols1734` (ID 69216272), with bypass permitted only through pull requests. Separate classic protection continues to enforce PRs, passing up-to-date CI, resolved conversations, linear history and no force pushes/deletions, including for administrators. No one-time weakening/restoration is needed under this final policy. Public security settings must still be verified after the visibility change. App Store distribution remains separately authorized work.

## What changed

- Completed the [pre-change exposure assessment](OPEN_SOURCE_SECURITY_ASSESSMENT.md), including full reachable Git history and ignored local fixture material.
- Added MIT licensing for project-owned work, including the owner-confirmed icon; retained Contributor Covenant attribution and documented third-party tools/content.
- Rewrote the README with actual simulator before/after screenshots, architecture, honest compatibility limits and reproducible development steps.
- Added contribution, private security disclosure, code of conduct and owner-only release guidance; four issue forms, a PR template and CODEOWNERS.
- Added locked development-only Playwright tooling, a combined layout runner, SwiftLint correctness rules, repository/dependency checks and an isolated native simulator test driver.
- Added least-privilege hosted CI for all PRs and `main`, without path filters that could skip required checks. The final `Required CI` gate fails if any job fails, is canceled or is skipped. No workflow uploads artifacts, receives release credentials, runs on personal hardware or publishes builds.
- Removed local workstation paths and hardcoded simulator IDs from current onboarding instructions. Historical metadata is preserved and disclosed; the owner approved the email as the reporting contact.

There are no changes to application source, app assets, entitlements, bundle ID, SDK requirement or Xcode project configuration.

## Verified GitHub configuration

| Setting | Result |
| --- | --- |
| Visibility | Private; no visibility mutation requested |
| Main protection | Required PR, one approving review, code-owner review, stale-review dismissal, approval after the latest push, resolved conversations, linear history |
| Required CI | `Required CI`, restricted to the GitHub Actions app (ID 15368), branch must be up to date |
| Admin enforcement | Enabled; direct pushes, force pushes and branch deletion are blocked by protection |
| Merge authority | Only `cnichols1734` is a repository collaborator, with admin access. No additional user/team access granted. CODEOWNERS names the owner for all files; it takes effect after the preparation PR reaches `main`. |
| Auto-merge | Disabled |
| Actions token | Read-only default; workflow PR approvals disabled; each workflow also requests only contents read |
| Actions trust | Selected actions only (`actions/checkout`, `actions/setup-node`), full-SHA pinning required; checkout credentials not persisted |
| Private fork PRs | Runs allowed with approval required, no write tokens, no secrets/variables passed |
| Dependabot alerts | Enabled |
| Dependabot security updates | Enabled, not paused; no auto-merge |
| Dependency update schedule | Weekly npm and GitHub Actions configuration prepared; activates once configuration is on the default branch. Downloaded scanner/linter tools are digest-pinned and require manual version review. |
| Discussions and issues | Enabled; requested labels configured |
| Release credentials | No Actions secrets, environments, deploy keys or webhooks found; none added |

## Limitations and owner decisions

1. **Secret scanning/push protection:** GitHub rejected enablement with “Secret scanning is not available for this repository.” These native controls are not enabled. The redacted Gitleaks CI scan is additional protection, not a pre-push block. Re-enable and verify both native settings immediately after separately approved public visibility, or use an eligible private plan/product.
2. **Private vulnerability reporting:** the private-repository endpoint returned 404. Public launch must enable and verify the form. Email disclosure is usable now and remains the fallback; no public issue is requested for vulnerabilities.
3. **Public fork approval policy:** GitHub rejected the all-external-contributors setting while private (422). The private-fork policy is enabled now. Set and verify `all_external_contributors` after publication, before approving external workflow runs. Do not expose secrets or use self-hosted runners.
4. **Owner-authored PRs (resolved by owner decision):** the original one-review policy blocked self-approval. The owner explicitly approved a permanent review-only exception for his individual account. The review ruleset still applies to everyone else; the separate PR/CI/integrity protection applies to the owner too. No new collaborator or broad administrator bypass was added. See `RELEASING.md` for the final governance policy.
5. **Personal history:** historical commits retain the author email, prior workspace path and local simulator identifier. No secrets were detected. Preserving history was recommended because these are not credentials; the final visibility approval must take this exposure into account.
6. **Runner availability:** `xcode-27` is a GitHub-hosted public-preview runner. Its published inventory includes Xcode 27.1 and the Duo 27.1 simulator. CI selects that toolchain explicitly and fails rather than silently skipping if it is unavailable. Public runner/billing availability is subject to the repository's account; do not replace it with a personal credential-bearing machine.
7. **Licensing policy:** the official project remains free, without ads/subscriptions/tracking. MIT still permits downstream commercial forks. Third-party website content in screenshots and Apple's SDKs/trademarks are not relicensed.

## Verification

Local results: Debug and Release simulator builds passed; 21 scroll, 12 archive and 19 data assertions passed (52 total); 24 gutter-layout and 14 camera-layout checks passed (38 total); SwiftLint correctness rules and actionlint passed; npm audit reported no known vulnerabilities in the locked development graph. The native simulator driver passed 30 integration checks, 1 persistence-write / 2 persistence-read checks across process termination, and 11 memory checks. No result is a physical-device or universal-site compatibility claim.

Hosted GitHub Actions [run 40534724010](https://github.com/cnichols1734/DuoBrowser/actions/runs/40534724010) passed all four jobs for preparation commit `cd5591c`: Repository and security, Layout regression tests, iOS build and native tests, and Required CI. The hosted runner compiled Debug/Release and passed the same 52 portable, 38 layout, 30 native, 3 persistence and 11 memory assertions. Its disposable simulator was cleaned up. Subsequent documentation-only commits still require their own green `Required CI` result before merge; the PR shows that current result.

The final full-history Gitleaks scan after adding the preparation commit found zero secrets. One unreachable local blob was also scanned with no findings. All relative Markdown links resolve, and a Git comparison confirms application source/assets and Xcode project files are byte-for-byte unchanged from `f168f4d`. API rechecks confirm private visibility, the configured protections, no additional collaborators, and no Actions secrets or environments.

## Publication checklist — requires explicit approval

- Use the approved owner-only review exception to merge the preparation PR after its final CI passes; verify both protection layers before changing visibility.
- Confirm the final code/license/docs/screenshots and green hosted CI, and acknowledge retained historical metadata.
- Obtain explicit owner approval to change the existing repository to public. Neither this document nor the preparation request is that approval.
- After approval, change visibility once, verify anonymous repository access, README/license/templates, and rerun/check CI.
- Re-read branch protections, collaborator access, Actions policy and auto-merge; enable/verify native secret scanning, push protection, private vulnerability reporting and approval for all external contributors.
- Confirm Dependabot configuration and Discussions are usable. Keep App Store credentials private and require separate release authorization.

## Sources checked

- [GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository)
- [Hosted Xcode 27 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
- [MIT License](https://opensource.org/license/mit) and [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct.html)

API responses and fully redacted scans remain in ignored local audit storage. This summary records observed results rather than assuming that a successful settings request enabled unsupported features.
