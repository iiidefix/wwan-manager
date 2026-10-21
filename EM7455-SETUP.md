# Setting up a Sierra Wireless EM7455 / Dell DW5811e

One-time setup of a new module before `wwan-manager` can use it: QMI
configuration, optional conversion of a DW5811e to the Sierra identity,
FCC lock and firmware update. Done by hand on the Pi on 2026-10-20 for both
modules here (an EM7455 and a DW5811e, now both on firmware 02.39.00.00 with
carrier configuration 002.085). Everything below uses the AT port
(`/dev/wwan-at`, here `ttyUSB2`) through `wwan-at`, or the QMI client
`/usr/lib/wwan-manager/qmi`.

`AT!` commands are Sierra's own; most of the ones below are undocumented
engineering commands. Each change takes effect after `AT!RESET`; after a
reset the modem stays on USB for about 12 s with its old state, then
disappears for a few seconds. Wait for `/dev/wwan-at` to come back before
the next command.

## 1. Identify the module

```sh
lsusb | grep -iE '1199|413c'          # 1199:9071 Sierra, 413c:81b6 Dell DW5811e
wwan-at ATI 'AT!ENTERCND="A710"' 'AT!USBCOMP?' 'AT!IMAGE?' 'AT!PRIID?' 'AT!PCINFO?' 'AT!PCFCCAUTH?'
```

- `ATI` shows model (`EM7455` / `EM7455B` for the DW5811e) and firmware.
- `AT!ENTERCND="A710"` unlocks the extended commands; send it before any
  other `AT!` command in the same `wwan-at` call.
- `AT!PCINFO?` lists the "low power mode" votes that keep the radio off:
  `BIOS` = FCC lock, `IMSWITCH` = firmware preference mismatch.

Both modules came in **MBIM** configuration. Before `wwan-manager` is installed
there is no `/dev/wwan-at`; use the ttyUSB port of USB interface 03
directly (`WWAN_AT_PORT=/dev/ttyUSB2 wwan-at …`, with `wwan-at` copied from
the package).

## 2. QMI configuration

`wwan-manager` needs the QMI USB configuration (diag, nmea, modem, rmnet0):

```sh
wwan-at 'AT!ENTERCND="A710"' 'AT!USBCOMP=1,1,0000010D' 'AT!RESET'
```

| Module | Before | After |
|---|---|---|
| EM7455 | `1,1,0000100D` (diag, nmea, modem, mbim) | `1,1,0000010D` |
| DW5811e | `1,1,0020100D` (diag, nmea, modem, mbim, ubist) | `1,1,0000010D` |

`AT!USBCOMP` is stored per USB identity: after converting a DW5811e
(step 3), set it again for the new identity. To go back to MBIM:
`AT!USBCOMP=1,1,0000100D` and `AT!RESET`.

## 3. DW5811e only: convert to the Sierra identity

Optional: `wwan-manager` also handles an unconverted DW5811e (`413c:81b6`).
Converting gives it the generic Sierra identity and carrier configuration,
so both modules behave the same:

```sh
wwan-at 'AT!ENTERCND="A710"' 'AT!USBVID=1199' 'AT!USBPID=9071,9070' \
	'AT!USBPRODUCT="EM7455"' 'AT!PRIID="9904609","002.026","Generic-Laptop"' 'AT!RESET'
# after the reset (now 1199:9071), the USB configuration of the new identity:
wwan-at 'AT!ENTERCND="A710"' 'AT!USBCOMP=1,1,0000010D' 'AT!RESET'
```

Only the resulting values below were recorded on 2026-10-20, not the exact
command lines: check each command's write syntax with `AT!<command>=?`
(e.g. `AT!USBPID=?`) before sending it, and compare with the query
(`AT!USBPID?`) afterwards.

| Setting | Dell | Sierra |
|---|---|---|
| `AT!USBVID` | `413C` | `1199` |
| `AT!USBPID` | app `81B6`, boot `81B5` | app `9071`, boot `9070` |
| `AT!USBPRODUCT` | `DW5811e Snapdragon™ X7 LTE` | `EM7455` |
| `AT!PRIID` | `9906458`, `001.004`, `Dell` | `9904609`, `002.026`, `Generic-Laptop` |

The DW5811e here already ran Sierra's generic firmware and carrier
configuration (`GENERIC_002.020_000`), so no firmware change was needed for
the conversion itself; it was updated afterwards (step 5).

## 4. FCC lock

Laptop modules can keep the radio off until the host sends the "FCC
authentication" (`BIOS:1` in `AT!PCINFO?`). `wwan-dial` sends the
per-session unlock (QMI DMS `0x555F`) before every dial, so a module with
the lock enabled works without this step. To disable the lock permanently
(done on the EM7455; the DW5811e had none):

1. Get a challenge:
   ```sh
   wwan-at 'AT!ENTERCND="A710"' 'AT!OPENLOCK?'
   ```
2. Compute the response key offline with sierrakeygen from
   [bkerler/edl](https://github.com/bkerler/edl)
   (`edlclient/Tools/sierrakeygen.py`, GPLv3), device generation `MDM9x30`:
   ```sh
   python3 sierrakeygen.py -l <challenge> -d MDM9x30
   ```
3. Unlock and switch the FCC authentication off:
   ```sh
   wwan-at 'AT!ENTERCND="A710"' 'AT!OPENLOCK="<key>"' 'AT!PCFCCAUTH=0'
   ```
   `AT!PCFCCAUTH?` shows `NV Setting: 0` at once; after `AT!RESET` also
   `FCC Auth Enabled: 0`, and the modem comes up online (`BIOS:0`,
   `CFUN: 1`) without any unlock.

To re-enable: the same `AT!OPENLOCK` step with a fresh challenge, then
`AT!PCFCCAUTH=1` and `AT!RESET`. The FCC lock exists for regulatory
reasons (radio certification together with the original host).

## 5. Firmware update

02.39.00.00 is the newest generic EM7455 firmware (Sierra's approved
packages, release 30). Use the complete package with firmware and carrier
configuration, `SWI9X30C_02.39.00.00_GENERIC_002.085_000.zip` (Sierra
account download, SHA-256 `afc394dd…d162bce`; a copy is in the project
root, and the unpacked files are in `/root/fw/` on the Pi):

- `SWI9X30C_02.39.00.00.cwe`: firmware, platform 9X30
- `SWI9X30C_02.39.00.00_GENERIC_002.085_000.nvu`: carrier configuration
  (PRI part `9904609`, must match `AT!PRIID?`)

Flash with `qmi-firmware-update` from `libqmi-utils` (1.36.0 here; not a
dependency of `wwan-manager`, install it for this), with LTE hung up:

```sh
ifdown wwan0
qmi-firmware-update --update -d 1199:9071 SWI9X30C_02.39.00.00.cwe SWI9X30C_02.39.00.00_GENERIC_002.085_000.nvu
```

The new image only becomes active after the modem's own restart following
the flash; wait for it to settle. The USB configuration (QMI) and a
disabled FCC lock are kept. Check:

```sh
wwan-at ATI 'AT!ENTERCND="A710"' 'AT!IMAGE?' 'AT!PRIID?' 'AT!USBCOMP?' 'AT!PCINFO?'
```

Expected: firmware 02.39.00.00, configuration and preference
`002.085_000`, carrier PRI stored, `0000010D`, no low-power votes.

**Firmware preference.** If the module's preferred firmware (QMI DMS
`0x0048`) names an image that isn't installed, the radio stays off
(`IMSWITCH` vote). The EM7455 here preferred `02.24.05.06_GENERIC` while
running 02.39.00.00; setting the preference to the running firmware with
`/usr/lib/wwan-manager/qmi /dev/cdc-wdm0 dms 0x0048 …` cleared the vote after
two modem restarts.

## 6. Radio settings

Settings the two modules here share (the DW5811e was aligned with the
EM7455 after its update):

```sh
wwan-at 'AT!ENTERCND="A710"' 'AT!SELRAT=06' 'AT!BAND=09' 'AT!PCOFFEN=2' \
	'AT+CGDCONT=1,"IPV4V6","internet.telekom"' 'AT!RESET'
```

| Setting | Value |
|---|---|
| `AT!SELRAT` | `06` LTE Only |
| `AT!BAND` | `09` LTE ALL |
| `AT!PCOFFEN` | `2` |
| `AT!CUSTOM` | GPSENABLE unset, FASTENUMEN `0x02`; GPSSEL, IPV6ENABLE, SIMLPM, USBSERIALENABLE, SINGLEAPNSWITCH = 1 |
| APN, context 1 (`AT+CGDCONT=1`) | `IPV4V6`, `internet.telekom` (1&1 accepts it too) |

`wwan-dial` starts context 1 (`QMI_PROFILE=1` in `/etc/default/wwan-manager`),
so the APN lives in the modem, not in `wwan-manager`'s settings. On a dual-SIM
carrier board, `wwan-sim` enables the second SIM interface when slot 2 is
first chosen (see [README.md](README.md#dual-sim)).

## 7. Check with wwan-manager

After installing `wwan-manager` (`/dev/wwan-at` and the interface name `wwan0`
come from its udev rules):

```sh
wwan-sim                       # SIM, operator, registration
ifup wwan0 && ping -c5 -I wwan0 1.1.1.1; ifdown wwan0
```

The setup survives reboots and power cuts: identity, QMI configuration,
disabled FCC lock and radio settings are stored in the module.
