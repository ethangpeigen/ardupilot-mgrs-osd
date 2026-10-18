# mgrs_osd.lua: MGRS position in the ArduPilot OSD

ArduPilot's OSD shows latitude and longitude in decimal degrees only. This script converts the position to **MGRS** and
sends it as a text message every few seconds. The OSD's **message panel** shows the latest message for about 10 seconds,
so with that panel enabled you see something like `MGRS 18S UJ 2348 0647` in your goggles. The same text also appears in
Mission Planner's Messages tab.

It does **not** replace the normal OSD, and it does not touch the flight controller's behaviour.

## Install

1. Copy **`mgrs_osd.lua`** (the `.lua`, not a `.md`) to `APM/scripts/` on the autopilot's SD card, e.g. with MAVFTP in Mission Planner.
2. Set `SCR_ENABLE = 1` (and `SCR_HEAP_SIZE` to 100000 or more if it is small) and reboot.
3. Refresh the parameter list. You get `MGRS_ENABLE`, `MGRS_PERIOD`, `MGRS_DIGITS`.
4. Turn on the OSD message panel on the screen you use: `OSDn_MESSAGE_EN = 1` (n = screen number) and place it with
   `OSDn_MESSAGE_X` / `OSDn_MESSAGE_Y`. On DisplayPort/HD systems also check `OSD_TYPE` and `MSP` settings as usual.
5. Reboot again if you changed the OSD layout. After a 3D GPS fix, the first message appears within `MGRS_PERIOD` seconds.

| Parameter | Default | Meaning |
|---|---|---|
| `MGRS_ENABLE` | 1 | 1 sends the position, 0 stays quiet |
| `MGRS_PERIOD` | 5 | seconds between messages (2..60); the OSD keeps a message for about 10 s |
| `MGRS_DIGITS` | 4 | 5 = 1 m, 4 = 10 m, 3 = 100 m, 2 = 1 km, 1 = 10 km |

## Replacing the latitude / longitude on the OSD

The script's text appears in the OSD **message panel**, so you can put that panel where the latitude and longitude are
now and switch those two items off. The OSD then shows the MGRS grid reference in their place.

1. Look up where your OSD draws the coordinates: `OSDn_GPSLAT_X` / `OSDn_GPSLAT_Y` and `OSDn_GPSLONG_X` /
   `OSDn_GPSLONG_Y` (n is the screen you use, usually 1; X is the column, Y is the row).
2. Move the message panel onto the latitude: set `OSDn_MESSAGE_X` and `OSDn_MESSAGE_Y` to the **latitude's X and Y**.
3. Turn the coordinates off: `OSDn_GPSLAT_EN = 0` and `OSDn_GPSLONG_EN = 0`.
4. Keep `MGRS_PERIOD` at 5 seconds or less. A message stays on screen for `OSD_MSG_TIME` seconds (10 by default), so the
   position is then nearly always visible.

Example (a DisplayPort/HD OSD, `OSD_TYPE = 5`) where the coordinates were drawn at column 9, rows 13 and 14:

| Parameter | Before | After |
|---|---|---|
| `OSD1_MESSAGE_X` | 2 | 9 |
| `OSD1_MESSAGE_Y` | 6 | 13 |
| `OSD1_GPSLAT_EN` | 1 | 0 |
| `OSD1_GPSLONG_EN` | 1 | 0 |

The MGRS line takes one row, so the second row (14 in the example) is left empty. Use `OSD1_MESSAGE_Y = 14` if you prefer the
text one row lower. Your own X/Y values will differ; copy the latitude's. If the text looks off by a column or two,
nudge `OSD1_MESSAGE_X`. This worked on a Walksnail-style DisplayPort OSD on ArduCopter 4.7; other OSD types are untested.

Other messages (a mode change, a pre-arm or battery warning) replace the MGRS text until the next update, because the
message panel shows only the most recent message.
## Limits

* The message line is shared with other alerts (flight mode changes, pre-arm warnings, battery warnings). Another message
  replaces the MGRS text until the next period.
* It sends one text message per period, so it also appears in the GCS and in the dataflash log. Raise `MGRS_PERIOD` to cut that down.
* No MGRS outside 80 S to 84 N (that region uses UPS). The script stays silent there.
* Needs a 3D fix (`gps:status` of 3 or more). The script uses the AHRS position when there is one.
* If another script already uses parameter table key **165**, change `PARAM_TABLE_KEY` at the top of the file.
* A script can also draw on the OSD itself (`osd:write`), but that takes over the whole screen from the normal OSD, so
  this version deliberately uses the message line instead.

## Testing

`test_mgrs_osd.py` runs the script in Lua 5.3 against a mock of the ArduPilot scripting API and compares it with the
`mgrs` reference library over about 20,000 positions (all zones, both hemispheres, the Norway and Svalbard exceptions,
1 to 5 digits): `pip install lupa mgrs`, then `python test_mgrs_osd.py`.

Result: every position matches except 26 that differ by 1 in the last digit where a position sits within millimetres of a cell edge. None is wrong by more than that.
It has **not been run on a real vehicle**.
