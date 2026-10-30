# Third-party notices and acquisition provenance

> **EDF-002 source adaptation (0.0.0-dev):** This document preserves the
> reviewed EzVM baseline procedure as a future operator reference. It is **not**
> a claim that an ezDarkFactory guest, WHPX, release, multi-factory manager or
> human workflow passed qualification. EDF-003/004 repair and guest-profile
> work, and later physical/release gates, remain outstanding. Runtime
> disks/credentials from the historical lab are never imported.


The normal ezDarkFactory 0.0.0-dev source package does **not** bundle QEMU, 7-Zip,
Ubuntu cloud images, VM disks, private keys, user credentials, or other
third-party binary payloads. ezdarkfactory downloads the reviewed artifacts directly
from their providers during bootstrap/base acquisition and verifies the
repository-pinned digests before use.

This file records provenance and upstream licensing references; it does not
relicense third-party software.

## QEMU for Windows

- Project: QEMU
- Windows provider used by the reviewed manifest: Stefan Weil QEMU for Windows
- Pinned ezdarkfactory provider artifact: QEMU 11.1.0, provider build 20260811
- Upstream project: https://www.qemu.org/
- Windows builds: https://qemu.weilnetz.de/w64/
- Licensing information: https://www.qemu.org/docs/master/about/license.html

The QEMU installer is downloaded and verified at runtime, then extracted into
repository-local generated state. It is not contained in the ezDarkFactory development source ZIP.

## 7-Zip extractor

- Project: 7-Zip
- Pinned ezdarkfactory version: 26.04
- Runtime bootstrap artifacts: official 7zr.exe and 7z2604-x64.exe
- Upstream project and licensing information: https://www.7-zip.org/

The extractor artifacts are downloaded and verified at runtime. They are not
contained in the ezDarkFactory development source ZIP.

## Ubuntu cloud image

- Provider: Canonical Ubuntu Cloud Images
- Guest baseline: Ubuntu Server 24.04 LTS (Noble) amd64
- Pinned publication: 20260926
- Pinned filename: ubuntu-24.04-server-cloudimg-amd64.img
- Pinned SHA-256:
  6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2
- Provider: https://cloud-images.ubuntu.com/releases/noble/

The cloud image is downloaded and verified into generated runtime/cache state.
It is not contained in the ezDarkFactory development source ZIP. Software inside Ubuntu remains
subject to the licenses of its respective packages and providers.
