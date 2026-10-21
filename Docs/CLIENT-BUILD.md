# Windows client edition

The portable client opens the existing local dashboard without installing Node.js or shipping loose application source files. It requires Windows 10/11 x64, PowerShell 5.1 and Microsoft Excel Desktop. Customer data stays in the workbook beside the executable.

This edition permits use through **2026-10-25 23:59:59.999 Africa/Cairo** and blocks new operations from **2026-10-26 00:00:00**, equivalent to `2026-10-25T21:00:00.000Z`. The developer launch is unaffected. The client enforces licensing in API middleware and again before starting each PowerShell job, including queued work. A configuration operation already in progress may finish safely.

Expired clients keep serving the activation UI. Renewals use an offline Ed25519 signature bound to a hash of the Windows MachineGuid. The private signing key is an owner-only deliverable; the client only embeds the public key. Signed renewal dates use the end of the chosen Cairo calendar day, including daylight-saving transitions.

## Build

Use Node.js **24.19.0 x64** for both the build host and the target executable. Obtain the target runtime and its `LICENSE` from [the official Node.js distribution](https://nodejs.org/dist/v24.19.0/), and verify its SHA-256 against the published `SHASUMS256.txt`.

```sh
npm ci
npm ci --prefix backend
npm ci --prefix frontend
npm run build --prefix backend
npm run build --prefix frontend
npm test
```

Obtain the [Posh-SSH v3.2.7 release](https://github.com/darkoperator/Posh-SSH/tree/v3.2.7), including its `Posh-SSH` module directory and `License.md`. It is bundled as an embedded dependency and extracted to the current user's local application data directory. Application PowerShell scripts run from memory and are never extracted to disk.

Use the original customer's `AP-Info-Manager.xlsx` or a validated empty template with `Sheet1`, the row-one headers documented in `how_to_work.txt`, and `Clients` in column K. The repository intentionally does not contain customer workbooks. The distributed sample is empty and must be populated before managing APs.

```sh
npm run build:client -- --target win-x64 \
  --node-binary /path/to/node.exe \
  --node-license /path/to/NODE-LICENSE \
  --ssh-module /path/to/Posh-SSH/Posh-SSH \
  --ssh-license /path/to/Posh-SSH/License.md \
  --workbook /path/to/AP-Info-Manager.xlsx \
  --keys-dir /private/ap-manager-signing \
  --out /path/to/distribution
```

The command creates separate client and owner directories. Distribute **only** `AP-Manager-Client-20261025`. Keep `AP-Manager-Owner-Only` private. Back up `activation-private-key.pem`, `activation-public-key.pem` and `state-secret` and reuse them for subsequent builds. The build rejects loose application source files, source maps and private signing keys in the client directory. It outputs a SHA-256 manifest.

`AP-Manager.exe --self-test` checks embedded assets without starting device operations. `--target linux-x64` is available only for packaging checks on a Linux build host. The production client rejects non-Windows normal launches. There is no client test-date flag, environment licensing toggle or unsigned activation override. Node execution argument extension is disabled.

## Issue a renewal

Double-click the owner activation tool, or run:

```text
AP-Manager-Activation.exe --machine APM-0123456789ABCDEF0123456789ABCDEF --customer "Client" --through 2026-12-31
```

The generated `.aplicense` contains the activation token to paste into the client's activation screen. It is valid through the end of the requested Cairo day. Activation persists in the current Windows user's local application data. Use the same Windows account for subsequent launches.

## Verification and limits

`npm test` covers the inclusive expiry boundary, first launch after expiry, valid renewal and restart, tampered signatures, wrong devices, expired/future activation, clock rollback, tampered/unwritable history, and enforcement on API calls and queued PowerShell work. Test clocks are dependency injection into unit tests and are not exposed in the executable.

The local high-water clock history detects ordinary clock rollback and history edits. A fully privileged machine owner can ultimately replace local state or reverse engineer a local executable; stronger enforcement requires a trusted licensing service. The original repository is public, so its original sources remain publicly accessible independently of this client package.

EXEs are unsigned. Apply a publisher certificate after packaging for a signed distribution. Excel COM and Cisco device behavior still require validation on the customer's actual Windows network; automated licensing tests do not establish that hardware integration.
