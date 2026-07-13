# Upstream maintenance

S-UI Next carries its own Web, API, authentication, subscription, and mobile changes, so upstream S-UI releases are reviewed and ported instead of merged wholesale. Core updates are handled as a coordinated dependency change.

## Tracked sources

- The latest stable [sing-box release](https://github.com/SagerNet/sing-box/releases) is the target core version.
- The sing-box version used by [alireza0/s-ui](https://github.com/alireza0/s-ui) is the compatibility reference for panel integration.
- The latest S-UI release is compared with `.github/upstream-tracking.json` so each upstream release is reviewed once, including changes that are not copied into this fork.
- The Cronet source commit in the Linux release workflow is compared separately with upstream S-UI. It is not interchangeable with the Cronet Go module pseudo-version.

The scheduled `Upstream dependency watch` workflow checks these sources daily. When versions diverge, it creates or updates one issue named `Upstream dependency updates available`. It closes that issue after the tracked versions are brought back into sync.

Dependabot groups sing-box, related SagerNet modules, Cronet modules, and `quic-go` into one pull request. This keeps compatibility-dependent updates together while leaving unrelated Go dependency updates independent.

## Update procedure

1. Create a dedicated integration branch from `main` and review upstream S-UI changes since `s_ui_reviewed_release`.
2. Update sing-box together with the versions adopted by upstream for `sing`, `sing-tun`, `sing-mux`, QUIC, Cronet, and any security-sensitive transitive dependencies.
3. Port relevant panel integration changes, migrations, build tags, and release toolchain changes. Do not overwrite fork-specific authentication, API, subscription, or mobile behavior with an upstream file-level merge.
4. Update the core version shown in both README files and synchronize `.github/upstream-tracking.json` after the upstream review is complete.
5. Open a pull request and let GitHub Actions run module consistency, backend tests, race checks, vulnerability scanning, frontend checks, and mobile builds.
6. For a sing-box minor release or a change to configuration semantics, publish a pre-release first and verify configuration generation, startup rollback, subscriptions, and representative protocols before promoting it.

Patch releases can follow the same path without a pre-release when upstream compatibility is unchanged and all release builds pass. Automatic monitoring may open an issue or dependency pull request, but core updates are never merged automatically.
