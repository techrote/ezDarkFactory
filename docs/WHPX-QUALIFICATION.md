# WHPX qualification procedure

> **EDF-002 source adaptation (0.0.0-dev):** This document preserves the
> reviewed EzVM baseline procedure as a future operator reference. It is **not**
> a claim that an ezDarkFactory guest, WHPX, release, multi-factory manager or
> human workflow passed qualification. EDF-003/004 repair and guest-profile
> work, and later physical/release gates, remain outstanding. Runtime
> disks/credentials from the historical lab are never imported.


EDF-002 runs no WHPX execution. Physical Windows/WHPX runtime qualification is **UNMEASURED**, never PASS. This procedure is a future qualification worksheet, not a receipt.

Use this procedure only on a compatible physical/local Windows 10 2004+ or
Windows 11 x86-64 client with firmware virtualization enabled and Windows
Hypervisor Platform installed.

## Preconditions

From a normal unelevated PowerShell session:

~~~powershell
.\ezdarkfactory.ps1 doctor -Json | ConvertFrom-Json
~~~

The host-os, hardware-virtualization, whpx, runtime-write, path, disk-space and
openssh-client checks should be ready. If WHPX is not enabled, enable it from an
elevated shell and reboot as documented in
[Getting started](GETTING-STARTED.md). Do not change QEMU security mitigations or
force an unsupported host into a PASS.

## Qualification

Use a fresh source checkout/package or a future reviewed clean working directory:

~~~powershell
.\ezdarkfactory.ps1 bootstrap
.\ezdarkfactory.ps1 base acquire
.\ezdarkfactory.ps1 base build
.\ezdarkfactory.ps1 create whpx-v01 -Profile normal
.\ezdarkfactory.ps1 start whpx-v01
.\ezdarkfactory.ps1 status whpx-v01 -Json | ConvertFrom-Json
.\ezdarkfactory.ps1 exec whpx-v01 -- sh -lc "printf 'WHPX_OK\n'; uname -a; git --version; python3 --version"
.\ezdarkfactory.ps1 stop whpx-v01
.\ezdarkfactory.ps1 diagnose whpx-v01 -CheckImage
.\ezdarkfactory.ps1 portability check
~~~

The public base build and start paths use WHPX; there is no silent TCG fallback.
Preserve the command outputs and QEMU/runtime evidence long enough to confirm:

- doctor reported WHPX configured;
- prepared-base construction completed under WHPX;
- start reached authenticated coding READY;
- runtime evidence records accelerator whpx;
- the guest command succeeded;
- graceful shutdown completed;
- stopped image/portability validation passed.

A TCG run, WHPX feature detection alone, or successful WHPX argv construction is
not equivalent evidence.

## Stop conditions

Stop and preserve diagnostics rather than weakening acceptance if any of these
occurs:

- doctor does not classify the host as supported/configured;
- QEMU reports WHPX initialization failure;
- lifecycle ownership is STALE/UNKNOWN;
- guest READY times out or identity/profile checks fail;
- storage/backing validation fails;
- graceful shutdown does not prove STOPPED;
- any step would require disabling a mitigation, changing guest acceptance
  criteria, force-opening a disk, deleting runtime evidence, or rebasing a chain
  merely to continue.

EDF-002 is not a release and has no WHPX PASS. Physical qualification remains a later EDF-011 gate.
