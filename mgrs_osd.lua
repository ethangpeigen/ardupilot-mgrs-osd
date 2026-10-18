-- mgrs_osd.lua
-- Shows the vehicle position as an MGRS grid reference in the OSD message line (and in your ground station's messages).
--
-- ArduPilot's own OSD can only show latitude / longitude in decimal degrees. This script converts the position to MGRS
-- and sends it as an ordinary text message every few seconds. The OSD's MESSAGE panel (OSDn_MESSAGE_EN) shows the most
-- recent text for a few seconds, so with the panel enabled you see e.g. "MGRS 18S UJ 2348 0647" in your goggles.
--
-- Install: copy this file to APM/scripts/ on the autopilot's SD card, set SCR_ENABLE = 1, reboot, then refresh the
-- parameter list. Parameters (prefix MGRS_):
--   MGRS_ENABLE   1 = send the position, 0 = stay quiet
--   MGRS_PERIOD   seconds between messages (2..60). The OSD shows a message for about 10 seconds
--   MGRS_DIGITS   digits per axis: 5 = 1 m, 4 = 10 m, 3 = 100 m, 2 = 1 km, 1 = 10 km
--
-- Needs a 3D GPS fix. Outside 80 S..84 N MGRS uses a different grid (UPS) and this script stays silent there.
-- Written for ArduPilot Lua (5.3). The conversion is the WGS84 transverse Mercator series used by common MGRS tools.

local PARAM_TABLE_KEY = 165  -- must be unique among the scripts on this vehicle (1..200); change it if another script uses 165
local PARAM_TABLE_PREFIX = "MGRS_"
local MAV_SEVERITY_INFO = 6
local GPS_FIX_3D = 3

assert(param:add_table(PARAM_TABLE_KEY, PARAM_TABLE_PREFIX, 3), "mgrs_osd: could not add the parameter table")
assert(param:add_param(PARAM_TABLE_KEY, 1, "ENABLE", 1), "mgrs_osd: could not add MGRS_ENABLE")
assert(param:add_param(PARAM_TABLE_KEY, 2, "PERIOD", 5), "mgrs_osd: could not add MGRS_PERIOD")
assert(param:add_param(PARAM_TABLE_KEY, 3, "DIGITS", 4), "mgrs_osd: could not add MGRS_DIGITS")
local P_ENABLE = Parameter("MGRS_ENABLE")
local P_PERIOD = Parameter("MGRS_PERIOD")
local P_DIGITS = Parameter("MGRS_DIGITS")

local floor, rad, sin, cos, tan, sqrt, min = math.floor, math.rad, math.sin, math.cos, math.tan, math.sqrt, math.min

-- WGS84 latitude / longitude (degrees) to MGRS, e.g. "18S UJ 2348 0647". digits = 1..5 per axis, truncated like real
-- MGRS. Returns nil outside 80 S..84 N.
local E2 = 0.0066943799901413
local EP2 = E2 / (1 - E2)
local E4, E6 = E2 * E2, E2 * E2 * E2
local M0 = 1 - E2 / 4 - 3 * E4 / 64 - 5 * E6 / 256
local M2 = 3 * E2 / 8 + 3 * E4 / 32 + 45 * E6 / 1024
local M4 = 15 * E4 / 256 + 45 * E6 / 1024
local M6 = 35 * E6 / 3072

local function to_mgrs(lat, lon, digits)
  if lat < -80 or lat >= 84 then return nil end
  digits = min(5, math.max(1, floor(digits)))
  local zone = floor((lon + 180) / 6) % 60 + 1
  if lat >= 56 and lat < 64 and lon >= 3 and lon < 12 then zone = 32 end -- Norway
  if lat >= 72 and lon >= 0 and lon < 42 then -- Svalbard
    zone = (lon < 9 and 31) or (lon < 21 and 33) or (lon < 33 and 35) or 37
  end
  local p = rad(lat)
  local cp, tp = cos(p), tan(p)
  local nu = 6378137 / sqrt(1 - E2 * sin(p) ^ 2)
  local t, c = tp * tp, EP2 * cp * cp
  local a = rad(lon - ((zone - 1) * 6 - 177)) * cp
  local a2 = a * a
  local m = 6378137 * (M0 * p - M2 * sin(2 * p) + M4 * sin(4 * p) - M6 * sin(6 * p))
  local x = 500000 + 0.9996 * nu * a * (1 + a2 * ((1 - t + c) / 6 + a2 * (5 - 18 * t + t * t + 72 * c - 58 * EP2) / 120))
  local y = 0.9996 * (m + nu * tp * a2 * (0.5 + a2 * ((5 - t + 9 * c + 4 * c * c) / 24 + a2 * (61 - 58 * t + t * t + 600 * c - 330 * EP2) / 720)))
  if lat < 0 then y = y + 10000000 end
  local band = min(20, floor((lat + 80) / 8) + 1)
  local k = (zone - 1) % 3 * 8 + floor(x / 100000)  -- column letter (24 letters, no I or O), 8 per zone set
  local r = (floor(y / 100000) + (zone % 2 == 0 and 5 or 0)) % 20 + 1 -- row letter (20 letters), even zones shifted
  local scale = 10 ^ (5 - digits)
  local ex = floor(x % 100000 / scale)
  local ny = floor(y % 100000 / scale)
  return string.format("%02d%s %s%s %0" .. digits .. "d %0" .. digits .. "d", zone,
    string.sub("CDEFGHJKLMNPQRSTUVWX", band, band),
    string.sub("ABCDEFGHJKLMNPQRSTUVWXYZ", k, k), string.sub("ABCDEFGHJKLMNPQRSTUV", r, r), ex, ny)
end

local function update()
  local period = floor(P_PERIOD:get() or 5)
  if period < 2 then period = 2 elseif period > 60 then period = 60 end
  if (P_ENABLE:get() or 0) >= 1 and gps:status(0) >= GPS_FIX_3D then
    local loc = ahrs:get_location()
    if loc then
      local text = to_mgrs(loc:lat() * 1e-7, loc:lng() * 1e-7, P_DIGITS:get() or 4)
      if text then gcs:send_text(MAV_SEVERITY_INFO, "MGRS " .. text) end
    end
  end
  return update, period * 1000
end

gcs:send_text(MAV_SEVERITY_INFO, "mgrs_osd: loaded")
return update, 5000
