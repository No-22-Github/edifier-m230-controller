# M230 II BLE protocol — hardware notes

Verified on one EDIFIER M230 Ⅱ, firmware **1.0.2**, using an Apple Silicon Mac on 2026-10-17. Device identifiers and addresses are intentionally omitted. This is community documentation, not an official Edifier specification.

## Discovery and transport

| Field | M230 II |
|---|---|
| Advertised service | `5703` |
| Manufacturer ID | `0x07E0` (`E0 07` on air) |
| Manufacturer data | company ID, six-byte Classic address, observed suffix `02 00` |
| Control service | `48095703-1A48-11E9-AB14-D663BD873D93` |
| Notify characteristic | `48090001-1A48-11E9-AB14-D663BD873D93` |
| Write characteristic | `48090002-1A48-11E9-AB14-D663BD873D93` |

Enable notifications before issuing queries. Use ATT write with response. CoreBluetooth exposes a per-host peripheral UUID, not the Classic address. The controller matches the `C8` response against the address in the selected BLE advertisement and verifies `C9 = EDIFIER M230 Ⅱ` before allowing writes.

Phone APP connections can prevent BLE control access from the Mac. Turning phone Bluetooth off made the control advertisement available during this session; Classic audio remained connected to the Mac. This is one-unit behavior, not a universal concurrency guarantee.

## Frames

```text
AA EC opcode length_hi length_lo payload… checksum    request
BB EC opcode length_hi length_lo payload… checksum    state response
```

Length is payload length, big-endian. Checksum is the low eight bits of the sum of all preceding frame bytes. Generic `CC EC` ACK framing is recognized by the parser, but ACKs are not accepted as device state. Notifications may be fragmented or contain multiple frames.

| Command | Request | Observed payload / meaning |
|---|---|---|
| D8 | `AA EC D8 00 00 6E` | 29-byte capability payload; queried but not fully interpreted |
| C9 | `AA EC C9 00 00 5F` | UTF-8 device name `EDIFIER M230 Ⅱ` |
| C8 | `AA EC C8 00 00 5E` | Six-byte Classic address; matched advertisement/system device |
| C6 | `AA EC C6 00 00 5C` | `01 00 02`, firmware 1.0.2 |
| D0 | `AA EC D0 00 00 66` | One-byte battery percent; `3C` = 60% matched the phone APP |
| D5 | `AA EC D5 00 00 6B` | `05` observed while DIY selected in the phone APP; other preset mappings untested |
| 43 | `AA EC 43 00 00 D9` | Custom EQ state, format 02 |
| 44 | One four-byte record | Set a single band, then query 43 to confirm |

A `44` ACK observed on hardware is `BB EC 44 00 01 01 ED`. ACK alone is not proof the desired value was stored.

## Six-band EQ format

Query payload begins `<format=02> <count=06>` followed by six four-byte records:

```text
index frequency_hi frequency_lo gain_code
```

The following is a neutral EQ payload without the optional suffix:

```text
02 06
00 00 3E 06
01 00 FA 06
02 03 E8 06
03 0F A0 06
04 1F 40 06
05 3E 80 06
```

Frequencies are 62, 250, 1000, 4000, 8000 and 16000 Hz. Gain is `(code − 6) × 0.5 dB`, where codes `00…0C` span −3…+3 dB. This scale comes from the phone APP, referenced implementations and matching hardware read/write values; it is not an acoustic frequency-response measurement.

The device can append timestamp/name bytes. The controller tolerates that suffix and never writes it.

Observed 62 Hz +0.5 dB request:

```text
AA EC 44 00 04 00 00 3E 07 23
```

Restore 62 Hz to 0 dB:

```text
AA EC 44 00 04 00 00 3E 06 22
```

All six bands were changed separately from 0 to +0.5 and restored to 0. Full-state read-back confirmed that the other five bands were unchanged. Later UI tests verified positive and negative changes, queued writes, six-band reset and restoration of the pre-test curve.

## Compatibility boundaries

S880DB MKII uses format 03 with six-byte band records; those records do not work unchanged here. MR5's documented `APP_CODE=06`, service `3A01` and nine-band parser also cannot be copied directly. M230 II accepted `AA EC` and service `5703` on this firmware.

The application does not send reset, power-off, OTA, source changes, codec changes or preset-switching commands. Original M230 (first generation), other speakers, renamed units and additional firmware versions have not been validated.

## Reference snapshots

| Repository | Commit consulted |
|---|---|
| [edf-controller](https://github.com/rioriost/edf-controller) | `56385cf6fb2f592d8867196bdaf0f88b131bd785` |
| [edifier-speakers-ble](https://github.com/kralonur/edifier-speakers-ble) | `51fd1d09475dc4beeec70aa8a3343ef3005f966c` |
| [omarchy-edifier-mr5](https://github.com/Devis99/omarchy-edifier-mr5) | `177e323279037549287b1125c9db37e28485e032` |
