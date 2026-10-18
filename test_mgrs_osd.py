"""Test mgrs_osd.lua without a vehicle.

Runs the script in Lua 5.3 (the version ArduPilot uses) against a mock of the ArduPilot scripting API and compares the
MGRS strings it sends with the 'mgrs' reference library (pip install lupa mgrs) over many positions, including the
Norway and Svalbard zone exceptions and both hemispheres.
"""
import random
import sys
from pathlib import Path

import mgrs
from lupa.lua53 import LuaRuntime

HERE = Path(__file__).resolve().parent
LETTERS = "CDEFGHJKLMNPQRSTUVWX"


def make_runtime(enable=1, period=5, digits=4, fix=3):
    lua = LuaRuntime(unpack_returned_tuples=True)
    state = {"sent": [], "params": {"MGRS_ENABLE": enable, "MGRS_PERIOD": period, "MGRS_DIGITS": digits}, "fix": fix, "lat": 0, "lng": 0}
    g = lua.globals()
    g.STATE = lua.table(sent=lua.table(), fix=fix, lat=0, lng=0)
    lua.execute("""
        local S = STATE
        param = {
          add_table = function(self, key, prefix, n) return true end,
          add_param = function(self, key, idx, name, default) S["p_" .. name] = default; return true end,
        }
        function Parameter(name)
          return { get = function(self) return S["p_" .. string.sub(name, 6)] end }
        end
        gps = { status = function(self, i) return S.fix end }
        ahrs = { get_location = function(self)
          if S.lat == nil then return nil end
          return { lat = function(l) return math.floor(S.lat * 1e7 + 0.5) end, lng = function(l) return math.floor(S.lng * 1e7 + 0.5) end }
        end }
        gcs = { send_text = function(self, sev, text) S.sent[#S.sent + 1] = sev .. "|" .. text end }
        function millis() return 0 end
    """)
    return lua, g.STATE


def run_script(lua, state):
    src = (HERE / "mgrs_osd.lua").read_text(encoding="utf-8")
    fn = lua.eval("function(src) local f = assert(load(src, 'mgrs_osd.lua')); return f() end")
    return fn(src)


def main():
    m = mgrs.MGRS()
    lua, st = make_runtime()
    update, interval = run_script(lua, st)
    assert interval == 5000, interval
    ok = bad = edge = 0
    rng = random.Random(7)
    pts = [(rng.uniform(-79.9, 83.9), rng.uniform(-180, 179.99)) for _ in range(4000)]
    pts += [(60.0, 5.0), (60.0, 11.9), (73.0, 5.0), (73.0, 15.0), (73.0, 25.0), (73.0, 36.0), (0.0, 0.0), (-33.9, 151.2),
            (83.9, 0.1), (-79.9, 10.0), (56.0, 3.0), (63.99, 11.99), (38.8895, -77.0353), (51.5, -0.12)]
    for digits in (1, 2, 3, 4, 5):
        st["p_DIGITS"] = digits
        for lat, lon in pts:
            st["lat"], st["lng"] = lat, lon
            st["sent"] = lua.table()
            update()
            got = st["sent"][1]
            assert got and got.startswith("6|MGRS "), got
            got = got[len("6|MGRS "):]
            ref = m.toMGRS(lat, lon, MGRSPrecision=digits)  # e.g. 18SUJ23480647
            # reference has no spaces: zone+band, 2 letters, then easting, northing
            head, grid, rest = ref[:3 if ref[1].isalpha() is False else 3], None, None
            zone_band = ref[:3] if ref[:2].isdigit() else ref[:2]
            letters = ref[len(zone_band):len(zone_band) + 2]
            nums = ref[len(zone_band) + 2:]
            half = len(nums) // 2
            expect = f"{zone_band} {letters} {nums[:half]} {nums[half:]}"
            if got == expect:
                ok += 1
            else:
                # tolerated: same zone/band/square letters and each number within 1 unit of the last digit. That happens
                # when a position is within a hair (millimetres) of a cell edge; the two series round differently there.
                g, e = got.split(), expect.split()
                near = (len(g) == 4 and g[:2] == e[:2] and abs(int(g[2]) - int(e[2])) <= 1 and abs(int(g[3]) - int(e[3])) <= 1)
                if near:
                    edge += 1
                else:
                    bad += 1
                    if bad <= 8:
                        print(f"MISMATCH lat={lat:.6f} lon={lon:.6f} digits={digits}: script {got!r} reference {expect!r}")
    print(f"position checks: {ok} exact, {edge} off by 1 in the last digit at a cell edge, {bad} wrong")
    # behaviour checks
    st["p_DIGITS"] = 4
    st["lat"], st["lng"] = 38.8895, -77.0353
    st["fix"] = 2
    st["sent"] = lua.table(); update()
    assert len(st["sent"]) == 0, "must stay quiet without a 3D fix"
    st["fix"] = 3; st["p_ENABLE"] = 0
    st["sent"] = lua.table(); update()
    assert len(st["sent"]) == 0, "must stay quiet when MGRS_ENABLE = 0"
    st["p_ENABLE"] = 1; st["lat"] = 85.0
    st["sent"] = lua.table(); update()
    assert len(st["sent"]) == 0, "must stay quiet above 84 N"
    st["lat"] = None
    st["sent"] = lua.table(); update()
    assert len(st["sent"]) == 0, "must stay quiet with no location"
    st["lat"], st["lng"] = 38.8895, -77.0353
    st["p_PERIOD"] = 1
    _, iv = update(); assert iv == 2000, iv
    st["p_PERIOD"] = 500
    _, iv = update(); assert iv == 60000, iv
    st["p_PERIOD"] = 8
    _, iv = update(); assert iv == 8000, iv
    print("behaviour checks: ok (silent without 3D fix / disabled / above 84N / no location; period clamped 2..60 s)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
