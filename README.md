# S-UI Next
**An Advanced Web Panel • Built on SagerNet/Sing-Box**

[English](README.md) | [简体中文](README.zh-CN.md)

## Highlights in this fork

S-UI Next is a downstream project that continues the original sing-box panel design while adding a versioned API, mobile apps, stronger authentication, richer analytics, and safer WireGuard management. The additions maintained here are listed first so the differences from the upstream project are immediately visible.

- Android arm64 and iPhone arm64 management apps with visual and raw JSON editors.
- Versioned `/apiv3` API covering resources, users, usage/statistics, logs, audit history, backup, and everyday tools.
- Cloudflare Zero Trust friendly custom headers in the app connection profile.
- User/date/search filters for usage, statistics, logs, audit records, and parsed connection details by user, inbound, outbound, endpoint, and destination.
- Searchable multi-level system logs and administrator change history in both Web and App.
- Granular subscription user-info controls for upload, download, quota, expiry, and node-name remaining quota.
- Per-client random subscription IDs, so public subscription URLs no longer expose or accept guessable usernames.
- OIDC single sign-on, TOTP two-factor authentication with one-time recovery codes, and WebAuthn passkeys.
- bcrypt password storage with automatic migration from legacy plaintext records after successful login.
- Web/App navigation parity: users, resources, TLS, core configuration, analytics, logs, administration, settings, and tools.
- Visual editors backed by optional raw JSON editing, including fields introduced by newer sing-box versions.
- Historical traffic views that remain stable until refreshed, plus an explicit real-time mode.
- Reworked WireGuard Endpoint management with separate server peer ownership and client routing fields, secure PSK generation/redaction, safe split-tunnel defaults, IPv4/IPv6 validation, explicit exported Endpoint host/port, controlled client configuration export, managed hub forwarding/site-gateway routes, and save/apply rollback.
- Localized Web and App interfaces in English, Farsi, Vietnamese, Simplified Chinese, Traditional Chinese, Russian, Japanese, French, and Latin.
- Tag-aware release filenames and seven intended GitHub Actions entries: five upstream workflows plus mobile CI and mobile application builds.

> Mobile source is available in [`mobile/`](mobile/README.md). Android arm64 and unsigned iPhone arm64 artifacts are built remotely by GitHub Actions. The app uses `/apiv3`, supports arbitrary request headers, and pre-fills Cloudflare Access Service Token headers.

## Milestones

- [x] Stable mobile API and secure token lifecycle.
- [x] Android arm64 and unsigned iPhone arm64 CI/release builds.
- [x] Visual editors and raw JSON fallback across Web and App.
- [x] Filterable analytics, structured logs, and dotted traffic charts.
- [x] OIDC, TOTP/2FA, recovery codes, and passkey management.
- [x] Safe WireGuard Endpoint editing, PSK/key handling, client export, managed hub/site routing, validation, and transactional apply.
- [x] Seven-workflow GitHub Actions layout: five upstream workflows plus mobile CI and mobile release builds.

## Release artifact naming

Tag builds include the tag in every downloadable filename, for example `s-ui-next-v1.2.0-linux-amd64.tar.gz`, `s-ui-next-v1.2.0-windows-amd64.zip`, `s-ui-next-v1.2.0-android-arm64.apk`, and `s-ui-next-v1.2.0-iphone-arm64-unsigned.ipa`.

![](https://img.shields.io/github/v/release/ciallothu/s-ui-next.svg)
[![Go Report Card](https://goreportcard.com/badge/github.com/ciallothu/s-ui-next)](https://goreportcard.com/report/github.com/ciallothu/s-ui-next)
[![Downloads](https://img.shields.io/github/downloads/ciallothu/s-ui-next/total.svg)](https://img.shields.io/github/downloads/ciallothu/s-ui-next/total.svg)
[![License](https://img.shields.io/badge/license-GPL%20V3-blue.svg?longCache=true)](https://www.gnu.org/licenses/gpl-3.0.en.html)

> **Disclaimer:** This project is only for personal learning and communication, please do not use it for illegal purposes, please do not use it in a production environment

**If you think this project is helpful to you, you may wish to give a**:star2:

**Want to contribute?** See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, coding conventions, testing, and the pull request process.

## Quick Overview
| Features                               |      Enable?       |
| -------------------------------------- | :----------------: |
| Multi-Protocol                         | :heavy_check_mark: |
| Multi-Language                         | :heavy_check_mark: |
| Multi-Client/Inbound                   | :heavy_check_mark: |
| Advanced Traffic Routing Interface     | :heavy_check_mark: |
| Client & Traffic & System Status       | :heavy_check_mark: |
| Subscription Link (link/json/clash + info)| :heavy_check_mark: |
| Dark/Light Theme                       | :heavy_check_mark: |
| Versioned API + Mobile Apps            | :heavy_check_mark: |
| OIDC, TOTP and Passkeys                | :heavy_check_mark: |
| Filtered Usage, Statistics and Logs    | :heavy_check_mark: |

## Supported Platforms
| Platform | Architecture | Status |
|----------|--------------|---------|
| Linux    | amd64, arm64, armv7, armv6, armv5, 386, s390x | ✅ Supported |
| Windows  | amd64, 386, arm64 | ✅ Supported |
| macOS    | amd64, arm64 | 🚧 Experimental |

## Screenshots

!["Main"](https://github.com/ciallothu/s-ui-next-frontend/raw/main/media/main.png)

[Other UI Screenshots](https://github.com/ciallothu/s-ui-next-frontend/blob/main/screenshots.md)

## API Documentation

[API-Documentation Wiki](https://github.com/ciallothu/s-ui-next/wiki/API-Documentation)

## Authentication configuration

Authentication features are configured from **Settings → Login & identity** and **Admins → Login security**. When the panel is behind a reverse proxy or Cloudflare Zero Trust, use the public HTTPS URL that users actually open in the browser.

### OIDC / SSO

Enable OIDC, then configure the issuer URL, client ID, client secret, scopes, username claim, and allowed identities. The redirect URL must exactly match the URL registered with the OIDC provider. For the default Web Path this is usually:

```text
https://panel.example.com/app/api/oidc-callback
```

If you changed the Web Path, keep that path in the callback URL, for example `https://panel.example.com/custom-path/api/oidc-callback`. The username claim defaults to `preferred_username`, then falls back to `email` and `sub`. Identities not matching an existing admin username must be listed in the allowed identities field.

### TOTP / 2FA

TOTP is managed from **Admins → Login security**. Enabling it shows an authenticator URI/secret and one-time recovery codes. Store the recovery codes immediately; each code can be used once when the normal 6-digit authenticator code is unavailable.

### WebAuthn passkeys

Enable passkeys in **Settings → Login & identity**, then add passkeys from **Admins → Login security**. RP ID and allowed origins can normally be left blank: S-UI Next auto-detects the current management domain from the browser origin and reverse-proxy headers such as `Forwarded`, `X-Forwarded-Host`, and `X-Forwarded-Proto`.

Manual configuration is still available for unusual proxy layouts. RP ID should be only the domain, for example `panel.example.com`; allowed origins should include full scheme origins, for example `https://panel.example.com`. Passkeys require HTTPS except for localhost-style development origins. The Web UI gives a best-effort automatic name such as iCloud Keychain, Google Password Manager, Windows Hello, or Security key; names can be renamed afterwards.

## WireGuard Endpoint configuration

The WireGuard editor follows the field semantics of the embedded sing-box `v1.13.12` Endpoint implementation:

- **Server Endpoint addresses** identify the S-UI Next side itself and should normally be an IPv4 `/32` and/or IPv6 `/128`, such as `10.66.66.1/32` and `fd66:66:66::1/128`.
- **Virtual network prefixes** are allocation ranges, such as `10.66.66.0/24` and `fd66:66:66::/64`. They are not written into the Endpoint `address` field.
- **Server peer allowed IPs** assign source addresses to one peer and therefore use unique host routes such as `/32` and `/128`.
- **Client AllowedIPs** choose destination traffic sent through the client tunnel. New peers default to the WireGuard virtual networks; `0.0.0.0/0` and `::/0` are only emitted after explicitly selecting the full-tunnel preset.
- **Client Endpoint host/port** must identify the real public WireGuard UDP entrypoint. It is deliberately independent from the Web panel hostname, which may be behind Cloudflare Access or an HTTP reverse proxy.
- **Regular clients** have no sing-box runtime peer address/port. WireGuard learns the current endpoint from handshakes, so this is suitable for phones, laptops, and NATed devices.
- **Fixed remote nodes** use a known remote WireGuard address and UDP port. Their server-side AllowedIPs normally remain the node’s own `/32` and/or `/128`.
- **Site gateways** represent a remote gateway plus one or more LAN prefixes behind it. The server runtime peer AllowedIPs include the gateway tunnel address plus the remote site CIDRs. The exported client configuration includes the S-UI Next WireGuard virtual networks and configured local site CIDRs, not the remote site’s own LAN.
- **PSK and private keys** are generated with backend secure randomness, hidden in ordinary API resource responses, preserved when saving redacted forms, and revealed only through explicit generation/copy/export actions.
- **Device forwarding through S-UI Next** is stored in a dedicated managed-route table and injected when the runtime configuration is generated. It means traffic is forwarded by this S-UI Next server between devices in the same Endpoint; it is not a direct device-to-device tunnel or NAT traversal feature. Equivalent user rules are not duplicated, and disabling the feature never deletes a user-authored rule.
- **Site-to-site routing** requires a return path on the local or remote LAN. If NAT is not configured separately, add a route such as `192.168.50.0/24 via <WireGuard gateway>` on the relevant network; otherwise only one-way traffic may be visible.

Use **Save** to keep a validated change without altering the current runtime. **Save & apply** validates the complete generated configuration, restarts the embedded core synchronously, checks the running state, and restores the previous runtime if application fails. Existing Endpoint JSON remains readable; the database migration adds only the managed-route table, while WireGuard editor metadata is stored compatibly in the existing Endpoint options.

## Default Installation Information
- Panel Port: 2095
- Panel Path: /app/
- Subscription Port: 2096
- Subscription Path: /sub/
- User/Password: admin

## Install & Upgrade to Latest Version

### Linux/macOS
```sh
bash <(curl -Ls https://raw.githubusercontent.com/ciallothu/s-ui-next/master/install.sh)
```

### Windows
1. Download the latest Windows release from [GitHub Releases](https://github.com/ciallothu/s-ui-next/releases/latest)
2. Extract the ZIP file
3. Run `install-windows.bat` as Administrator
4. Follow the installation wizard

## Install legacy Version

**Step 1:** To install your desired legacy version, add the version to the end of the installation command. e.g., ver `1.0.0`:

```sh
VERSION=1.0.0 && bash <(curl -Ls https://raw.githubusercontent.com/ciallothu/s-ui-next/$VERSION/install.sh) $VERSION
```

## Manual installation

### Linux/macOS
1. Get the latest version of S-UI Next based on your OS/Architecture from GitHub: [https://github.com/ciallothu/s-ui-next/releases/latest](https://github.com/ciallothu/s-ui-next/releases/latest)
2. **OPTIONAL** Get the latest version of `s-ui-next.sh` [https://raw.githubusercontent.com/ciallothu/s-ui-next/master/s-ui-next.sh](https://raw.githubusercontent.com/ciallothu/s-ui-next/master/s-ui-next.sh)
3. **OPTIONAL** Copy `s-ui-next.sh` to /usr/bin/ and run `chmod +x /usr/bin/s-ui-next`.
4. Extract s-ui-next tar.gz file to a directory of your choice and navigate to the directory where you extracted the tar.gz file.
5. Copy *.service files to /etc/systemd/system/ and run `systemctl daemon-reload`.
6. Enable autostart and start S-UI Next service using `systemctl enable s-ui-next --now`
7. Start sing-box service using `systemctl enable sing-box --now`

### Windows
1. Get the latest Windows version from GitHub: [https://github.com/ciallothu/s-ui-next/releases/latest](https://github.com/ciallothu/s-ui-next/releases/latest)
2. Download the appropriate Windows package (e.g., `s-ui-next-windows-amd64.zip`)
3. Extract the ZIP file to a directory of your choice
4. Run `install-windows.bat` as Administrator
5. Follow the installation wizard
6. Access the panel at http://localhost:2095/app

## Uninstall S-UI Next

```sh
sudo -i

systemctl disable s-ui-next  --now

rm -f /etc/systemd/system/sing-box.service
systemctl daemon-reload

rm -fr /usr/local/s-ui-next
rm /usr/bin/s-ui-next
```

## Install using Docker

<details>
   <summary>Click for details</summary>

### Usage

**Step 1:** Install Docker

```shell
curl -fsSL https://get.docker.com | sh
```

**Step 2:** Install S-UI Next

> Docker compose method

```shell
mkdir s-ui-next && cd s-ui-next
wget -q https://raw.githubusercontent.com/ciallothu/s-ui-next/master/docker-compose.yml
docker compose up -d
```

> Use docker

```shell
mkdir s-ui-next && cd s-ui-next
docker run -itd \
    -p 2095:2095 -p 2096:2096 -p 443:443 -p 80:80 \
    -v $PWD/db/:/app/db/ \
    -v $PWD/cert/:/root/cert/ \
    --name s-ui-next --restart=unless-stopped \
    ghcr.io/ciallothu/s-ui-next:latest
```

> Build your own image

```shell
git clone https://github.com/ciallothu/s-ui-next
git submodule update --init --recursive
docker build -t s-ui-next .
```

</details>

## Manual run ( contribution )

<details>
   <summary>Click for details</summary>

### Build and run whole project
```shell
./runSUI.sh
```

### Clone the repository
```shell
# clone repository
git clone https://github.com/ciallothu/s-ui-next
# clone submodules
git submodule update --init --recursive
```


### - Frontend

Visit [s-ui-next-frontend](https://github.com/ciallothu/s-ui-next-frontend) for frontend code

### - Backend
> Please build frontend once before!

To build backend:
```shell
# remove old frontend compiled files
rm -fr web/html/*
# apply new frontend compiled files
cp -R frontend/dist/ web/html/
# build
go build -o sui main.go
```

To run backend (from root folder of repository):
```shell
./sui
```

</details>

## Languages

- English
- Farsi
- Vietnamese
- Chinese (Simplified)
- Chinese (Traditional)
- Japanese
- French
- Latin
- Russian

## Features

- Supported protocols:
  - General:  Mixed, SOCKS, HTTP, HTTPS, Direct, Redirect, TProxy
  - V2Ray based: VLESS, VMess, Trojan, Shadowsocks
  - Other protocols: ShadowTLS, Hysteria, Hysteria2, Naive, TUIC
- Supports XTLS protocols
- An advanced interface for routing traffic, incorporating PROXY Protocol, External, and Transparent Proxy, SSL Certificate, and Port
- An advanced interface for inbound and outbound configuration
- Clients’ traffic cap and expiration date
- Displays online clients, inbounds and outbounds with traffic statistics, and system status monitoring
- Subscription service with ability to add external links and subscription
- HTTPS for secure access to the web panel and subscription service (self-provided domain + SSL certificate)
- Dark/Light theme

## Environment Variables

<details>
  <summary>Click for details</summary>

### Usage

| Variable       |                      Type                      | Default       |
| -------------- | :--------------------------------------------: | :------------ |
| SUI_LOG_LEVEL  | `"debug"` \| `"info"` \| `"warn"` \| `"error"` | `"info"`      |
| SUI_DEBUG      |                   `boolean`                    | `false`       |
| SUI_BIN_FOLDER |                    `string`                    | `"bin"`       |
| SUI_DB_FOLDER  |                    `string`                    | `"db"`        |
| SINGBOX_API    |                    `string`                    | -             |

</details>

## SSL Certificate

<details>
  <summary>Click for details</summary>

### Certbot

```bash
snap install core; snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

certbot certonly --standalone --register-unsafely-without-email --non-interactive --agree-tos -d <Your Domain Name>
```

</details>

## Stargazers over Time
[![Stargazers over time](https://starchart.cc/ciallothu/s-ui-next.svg)](https://starchart.cc/ciallothu/s-ui-next)
