# Setting up a Sierra Wireless EM7455 / Dell DW5811e

One-time setup of a new module before `wwan-manager` can use it: installing
the package, the QMI configuration, optional conversion of a DW5811e to the
Sierra identity, the FCC lock, the firmware, the radio settings and APN, and a
final check. Every step starts with a check of the module's current state, so
a module that is already set up can skip it. Everything below uses the AT port
(`/dev/wwan-at`, normally `ttyUSB2`) through `wwan-at`, or the QMI client
`/usr/lib/wwan-manager/qmi`.

`AT!` commands are Sierra's own; most of the ones below are undocumented
engineering commands. Each change takes effect after `AT!RESET`; after a
reset the modem stays on USB for about 12 s with its old state, then
disappears for a few seconds. Wait for `/dev/wwan-at` to come back before
the next command.

## 0. Install wwan-manager

```sh
dpkg -i wwan-manager_*.deb
```

`dpkg` asks for the package's settings (debconf); the defaults are fine for
this guide, and they can be changed later (`dpkg-reconfigure -plow
wwan-manager`). The package needs only tools a Debian system already has, so
nothing is downloaded.

Check: `ip -br a show wwan0` lists `wwan0` if the modem is plugged in (the
package's udev rule names its network interface), and
`cat /etc/network/interfaces.d/wwan-manager` contains `iface wwan0 inet
manual`.

**ModemManager.** Some images ship it, enabled. It probes every modem it knows
(it has rules for Sierra modems) and opens the modem's AT and control ports
itself, and it has been seen switching the USB configuration of a Huawei module.
That gets in the way of `wwan-at`, the QMI client and the USB changes below.
Stop it for the setup and keep it away from the modem afterwards:

```sh
systemctl disable --now ModemManager       # or: systemctl mask ModemManager
```

Check: `systemctl is-active ModemManager` prints `inactive`.

## 1. Identify the module

```sh
lsusb | grep -iE '1199|413c'          # 1199:9071 Sierra, 413c:81b6 Dell DW5811e
ls -l /dev/wwan-at                    # -> ttyUSB2; missing: see step 2, "MBIM only"
wwan-at ATI 'AT!ENTERCND="A710"' 'AT!USBCOMP?' 'AT!IMAGE?' 'AT!PRIID?' 'AT!PCINFO?' 'AT!PCFCCAUTH?'
```

- `ATI` shows model (`EM7455` / `EM7455B` for the DW5811e) and firmware.
- `AT!ENTERCND="A710"` unlocks the extended commands; send it before any
  other `AT!` command in the same `wwan-at` call.
- `AT!PCINFO?` lists the "low power mode" votes that keep the radio off:
  `BIOS` = FCC lock, `IMSWITCH` = firmware preference mismatch.

Modules usually come in **MBIM** configuration with serial ports (AT port
`ttyUSB2`; without the package's udev rule use
`WWAN_AT_PORT=/dev/ttyUSB2 wwan-at …`). Some come **MBIM only**: `lsusb -t`
shows just `cdc_mbim` (interfaces 12 and 13) and there is no `/dev/ttyUSB*`,
so no AT port; see "MBIM only" in step 2.

## 2. QMI configuration

`wwan-manager` needs the QMI USB configuration (diag, nmea, modem, rmnet0).
Current status:

```sh
lsusb -t | grep -E 'qcserial|qmi_wwan|cdc_mbim'    # qmi_wwan = QMI, cdc_mbim = MBIM
wwan-at 'AT!ENTERCND="A710"' 'AT!USBCOMP?'         # ends in …010D = QMI, …100D = MBIM
```

If it is already QMI, skip this step. Otherwise:

```sh
wwan-at 'AT!ENTERCND="A710"' 'AT!USBCOMP=1,1,0000010D' 'AT!RESET'
```

Check: after the reset (wait for `/dev/wwan-at`), `lsusb -t` shows
`qcserial` (3 ports) and `qmi_wwan`, and `AT!USBCOMP?` ends in `…010D`.

**MBIM only (no AT port).** The AT port is not there to switch the
configuration, but the module answers QMI through the MBIM port. This needs
`qmicli` (`apt install libqmi-utils`, the only package installed from the
internet in this guide; the same package also provides `qmi-firmware-update`
for step 5):

```sh
qmicli -d /dev/cdc-wdm0 --device-open-mbim --dms-get-model              # EM7455B
qmicli -d /dev/cdc-wdm0 --device-open-mbim --dms-swi-get-usb-composition
# lists the compositions; [*] marks the active one, here "9: MBIM"
qmicli -d /dev/cdc-wdm0 --device-open-mbim --dms-swi-set-usb-composition=6
# 6 = DM, NMEA, AT, QMI
qmicli -d /dev/cdc-wdm0 --device-open-mbim --dms-set-operating-mode=offline
qmicli -d /dev/cdc-wdm0 --device-open-mbim --dms-set-operating-mode=reset
```

One option per `qmicli` call. The last call may end with "Transaction timed
out" because the modem resets under it; that is fine. After about 25 s
`/dev/ttyUSB0-2` and `/dev/wwan-at` exist and the module is in the QMI
configuration (check as above). Its bitmask `AT!USBCOMP?` is then
`0020010D` (QMI plus `ubist`), which works as is.

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
so both modules behave the same. Current status:

```sh
lsusb | grep -iE '1199|413c'     # 1199:9071 = converted, 413c:81b6 = Dell identity
wwan-at 'AT!ENTERCND="A710"' 'AT!USBVID?' 'AT!USBPID?' 'AT!USBPRODUCT?' 'AT!PRIID?'
```

Compare with the table below. Converted already: skip this step. Otherwise:

```sh
wwan-at 'AT!ENTERCND="A710"' 'AT!USBVID=1199' 'AT!USBPID=9071,9070' \
	'AT!USBPRODUCT="EM7455"' 'AT!PRIID="9904609","002.026","Generic-Laptop"' 'AT!RESET'
# after the reset (now 1199:9071), the USB configuration of the new identity:
wwan-at 'AT!ENTERCND="A710"' 'AT!USBCOMP=1,1,0000010D' 'AT!RESET'
```

Only the resulting values below were recorded, not the exact command lines:
check each command's write syntax with `AT!<command>=?`
(e.g. `AT!USBPID=?`) before sending it, and compare with the query
(`AT!USBPID?`) afterwards.

| Setting | Dell | Sierra |
|---|---|---|
| `AT!USBVID` | `413C` | `1199` |
| `AT!USBPID` | app `81B6`, boot `81B5` | app `9071`, boot `9070` |
| `AT!USBPRODUCT` | `DW5811e Snapdragon™ X7 LTE` | `EM7455` |
| `AT!PRIID` | `9906458`, `001.004`, `Dell` | `9904609`, `002.026`, `Generic-Laptop` |

A DW5811e may already run Sierra's generic firmware and carrier
configuration (`GENERIC_002.020_000`), so no firmware change was needed for
the conversion itself; it was updated afterwards (step 5).

## 4. FCC lock

Laptop modules can keep the radio off until the host sends the "FCC
authentication" (`BIOS:1` in `AT!PCINFO?`). `wwan-dial` sends the
per-session unlock (QMI DMS `0x555F`) before every dial, so a module with
the lock enabled works without this step.

Check whether the module has the lock:

```sh
wwan-at 'AT!ENTERCND="A710"' 'AT!PCFCCAUTH?' 'AT!PCINFO?'
```

- `FCC Auth Enabled: 0` and `BIOS:0` in the "LPM voters" line: no lock,
  nothing to do; skip the rest of this step.
- `FCC Auth Enabled: 1`: the lock is enabled. `BIOS:1` means the radio is
  off right now (the per-session unlock was not sent yet). Both are fine for
  `wwan-manager`; continue only to remove the lock permanently.

To disable the lock permanently (done on the EM7455; the DW5811e had none):

1. Get a challenge:
   ```sh
   wwan-at 'AT!ENTERCND="A710"' 'AT!OPENLOCK?'
   ```
2. Compute the response key offline with sierrakeygen from
   [bkerler/edl](https://github.com/bkerler/edl)
   (`edlclient/Tools/sierrakeygen.py`, GPLv3), device generation `MDM9x30`.
   It needs the Python modules `pyserial`, `Exscript` and `colorama`, so run
   it on another machine rather than on the module's host:
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
packages, release 30). Check what the module runs:

```sh
wwan-at ATI 'AT!ENTERCND="A710"' 'AT!IMAGE?'
```

- `Revision: SWI9X30C_02.39.00.00 …` in `ATI`, and `AT!IMAGE?` listing
  `02.39.00.00` for the FW slot and the `PRI` line (`…_GENERIC`): up to
  date, skip the rest of this step.
- Anything older (e.g. `02.24.03.00`): update. This is optional;
  `wwan-manager` dials with older firmware too (checked with 02.24.03.00).

Use the complete package with firmware and carrier
configuration, `SWI9X30C_02.39.00.00_GENERIC_002.085_000.zip` (Sierra
account download, SHA-256 `afc394dd…d162bce`), unpacked on the module's host:

- `SWI9X30C_02.39.00.00.cwe`: firmware, platform 9X30
- `SWI9X30C_02.39.00.00_GENERIC_002.085_000.nvu`: carrier configuration
  (PRI part `9904609`, must match `AT!PRIID?`)

Flash with `qmi-firmware-update` from `libqmi-utils` (not a dependency of
`wwan-manager`, install it for this), with LTE hung up and ModemManager
stopped (step 0):

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
(`IMSWITCH` vote). An EM7455 preferred `02.24.05.06_GENERIC` while
running 02.39.00.00; setting the preference to the running firmware with
`/usr/lib/wwan-manager/qmi /dev/cdc-wdm0 dms 0x0048 …` cleared the vote after
two modem restarts.

## 6. Radio settings

Settings an EM7455 and a DW5811e (after the firmware update) share. Current
status (compare with the table below):

```sh
wwan-at 'AT!ENTERCND="A710"' 'AT!SELRAT?' 'AT!BAND?' 'AT!PCOFFEN?' 'AT!CUSTOM?' 'AT+CGDCONT?'
```

To set them:

```sh
wwan-at 'AT!ENTERCND="A710"' 'AT!SELRAT=06' 'AT!BAND=09' 'AT!PCOFFEN=2' \
	'AT+CGDCONT=1,"IPV4V6","internet.telekom"' 'AT!RESET'
```

| Setting | Value |
|---|---|
| `AT!SELRAT` | `06` LTE Only |
| `AT!BAND` | `09` LTE ALL |
| `AT!PCOFFEN` | `2` |
| `AT!CUSTOM` | GPSENABLE unset, FASTENUMEN `0x02`; GPSSEL, IPV6ENABLE, SIMLPM, USBSERIALENABLE, SINGLEAPNSWITCH = 1 (`IPV6ENABLE` is needed for `IPV6=yes`) |
| APN, context 1 (`AT+CGDCONT=1`) | `IPV4V6` and your carrier's APN (`internet.telekom` for Telekom.de) |

`wwan-dial` starts context 1 (`QMI_PROFILE=1` in `/etc/default/wwan-manager`;
`wwan-dial up --profile N` and `wwan-apn --profile N` use another one),
so the APN lives in the modem, not in `wwan-manager`'s settings. `wwan-apn
<apn>` sets it (see step 7) and checks the result. On a dual-SIM
carrier board, `wwan-sim` enables the second SIM interface when slot 2 is
first chosen (see [README.md](README.md#dual-sim)).

## 7. Check with wwan-manager

After installing `wwan-manager` (`/dev/wwan-at` and the interface name `wwan0`
come from its udev rules):

```sh
wwan-sim                       # current status: SIM, operator, registration
wwan-pin                       # SIM state and PIN lock; the SIM must have no PIN
wwan-apn                       # current status: APN of context 1
wwan-apn <apn>                 # APN of context 1, your carrier's
ifup wwan0 && ping -c5 -I wwan0 1.1.1.1; ifdown wwan0
```

Checks:

- `wwan-at AT+CPIN? AT+COPS? AT+CEREG?` → `READY`, your operator with
  access technology `7` (LTE), `+CEREG: 0,1` (registered). A wrong APN makes
  the dial fail quietly: check the APN first.
- `wwan-apn` → `context 1: APN <apn>, PDP type IPV4V6`.
- `ifup wwan0` → `wwan-dial: wwan0: up, <address>/<prefix>`; `ip route show
  table 700` has `default via … dev wwan0 metric 700`.
- `ping -I wwan0` gets answers.
- `ifdown wwan0` → `wwan-dial: wwan0: hung up`, `ip -br a show wwan0` is `DOWN`.

Optional IPv6, for a carrier that supports it and a profile of PDP type
`IPV4V6` (set above): dial once with it switched on, as the environment is
not passed through `ifup` (see the README):

```sh
IPV6=yes wwan-dial up && ping -6 -c3 -I wwan0 2001:4860:4860::8888; wwan-dial down
```

`wwan-dial: wwan0: IPv6 up, <address>/<prefix>` shows it worked; if the carrier
or the module refuses, it logs `no IPv6 … IPv4 only` and the IPv4 connection
is unaffected. To make it permanent, set `IPV6=yes` in
`/etc/default/wwan-manager`.

The setup survives reboots and power cuts: identity, QMI configuration,
disabled FCC lock and radio settings are stored in the module.
