# Getting started with ezDarkFactory developer CLI (0.0.0-dev)

> **EDF-002 source adaptation (0.0.0-dev):** This document preserves the
> reviewed EzVM baseline procedure as a future operator reference. It is **not**
> a claim that an ezDarkFactory guest, WHPX, release, multi-factory manager or
> human workflow passed qualification. EDF-003/004 repair and guest-profile
> work, and later physical/release gates, remain outstanding. Runtime
> disks/credentials from the historical lab are never imported.


ezdarkfactory manages disposable Ubuntu coding VMs from a normal Windows folder. The
public control path supports Windows PowerShell 5.1 and current PowerShell 7.

## Host prerequisites

Use a Windows 10 2004+ or Windows 11 x86-64 client host with:

- CPU virtualization enabled in firmware;
- Windows Hypervisor Platform (WHPX) enabled for normal VM starts;
- the Windows OpenSSH Client (ssh.exe, scp.exe, ssh-keygen.exe);
- a local NTFS-like filesystem with at least 20 GiB free for practical use;
- normal user write access to the ezdarkfactory folder.

ezdarkfactory does not enable Windows features automatically. From an elevated shell,
WHPX can be enabled with:

~~~powershell
DISM /online /Enable-Feature /FeatureName:HypervisorPlatform /All
~~~

Reboot if Windows requests it. Then return to a normal unelevated PowerShell
session.

## Bootstrap a fresh checkout

From the ezdarkfactory folder:

~~~powershell
.\ezdarkfactory.ps1 version
.\ezdarkfactory.ps1 doctor
.\ezdarkfactory.ps1 bootstrap
.\ezdarkfactory.ps1 base acquire
.\ezdarkfactory.ps1 base build
~~~

bootstrap downloads the reviewed QEMU and 7-Zip provider artifacts and verifies
their pinned digests before extraction. base acquire downloads the pinned
Ubuntu 24.04 LTS cloud image and verifies its SHA-256. base build provisions a
new immutable coding base; it does not modify the upstream source image.

doctor reports prerequisite evidence only. It does not enable WHPX and does not
claim that WHPX execution succeeded merely because the feature is enabled.

## Create and use a coding VM

~~~powershell
.\ezdarkfactory.ps1 create work
.\ezdarkfactory.ps1 start work
.\ezdarkfactory.ps1 exec work -- git --version
.\ezdarkfactory.ps1 copy-to work .\input.txt /home/coder/workspace/input.txt
.\ezdarkfactory.ps1 copy-from work /home/coder/workspace/input.txt .\roundtrip.txt
.\ezdarkfactory.ps1 ssh work
.\ezdarkfactory.ps1 stop work
~~~

The default resource profile is normal (4 vCPU, 8 GiB RAM). start returns only
after authenticated localhost SSH, exact guest identity, current-boot
finalization, cloud-init completion, and live coding-profile checks succeed.

Guest user coder has passwordless sudo **inside the guest**. There is no shared
host filesystem by default and SSH forwarding binds only to 127.0.0.1.

## Disposable and portable state

After an instance is positively stopped:

~~~powershell
.\ezdarkfactory.ps1 reset work
.\ezdarkfactory.ps1 clone work work-fresh -Mode fresh
.\ezdarkfactory.ps1 clone work work-stateful -Mode stateful
.\ezdarkfactory.ps1 export work-stateful C:\Exports\work-stateful
.\ezdarkfactory.ps1 import imported C:\Exports\work-stateful\disk.qcow2 -ManifestPath C:\Exports\work-stateful\manifest.json
.\ezdarkfactory.ps1 portability check
~~~

A fresh clone uses the source instance's existing immutable baseline and excludes
later overlay changes. A stateful clone/export intentionally preserves guest disk
state and can preserve credentials; treat it as sensitive.

For cold portability, cleanly stop **every** VM, run portability check, copy the
complete ezdarkfactory working directory to the other compatible Windows host/path, run
doctor and portability check again, then start the required instance. Do not
copy a live VM disk or treat stale PID files as proof of a clean stop.

## Diagnosis and recovery

~~~powershell
.\ezdarkfactory.ps1 status work
.\ezdarkfactory.ps1 diagnose work
.\ezdarkfactory.ps1 diagnose work -CheckImage
~~~

diagnose is observation-only. It never repairs, force-opens, rebases, commits,
or clears ambiguous runtime ownership. See [Troubleshooting](TROUBLESHOOTING.md)
before touching interrupted reset/clone/import/export evidence.

## v0.1 compatibility and upgrades

New durable instances use instance.json schema version 2 with an explicit
identity generation. Complete schema version 1 instances remain readable under
their documented compatibility rules; old unsupported provisioning identities
are not silently rewritten.

EDF-011 introduced a verified QEMU payload inventory. A QEMU runtime created by
an older ezdarkfactory build without that inventory must be preserved outside
runtime/qemu and rebuilt with bootstrap; existing bases, instance disks and
controller keys are not rewritten by that rebootstrap.

The unqualified development source ZIP contains first-party source/control-plane material,
manifests and documentation only. It deliberately excludes downloaded QEMU,
Ubuntu images, VM disks, runtime state and private keys. A user's *working
directory* is separately cold-portable after every VM is stopped.

## Limits

v0.1 does not provide live migration, suspend-state portability, bridged/TAP
networking, GPU/USB passthrough, Windows guests, ARM support, or a guarantee
against hypervisor/guest-kernel escape. Historical EzVM hosted release qualification (not EDF-002) uses QEMU
TCG for orchestration and explicitly does not claim a WHPX runtime PASS. See
[WHPX qualification](WHPX-QUALIFICATION.md) for the supported-host procedure.
