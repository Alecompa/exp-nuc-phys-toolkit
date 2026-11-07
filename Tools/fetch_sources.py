"""Snapshot gamma and X-ray emissions of common calibration sources from the IAEA LiveChart API
(ENSDF decay data) into the JSON bundled with NucPhysKit.

Raw API responses are kept in Data/LiveChart/ so the conversion is reproducible offline.
Usage:
  python3 -I Tools/fetch_sources.py Data/LiveChart Packages/NucToolkit/Sources/NucPhysKit/Resources/calibration_sources.json
  (add --offline to rebuild from the saved CSVs)
"""
import csv, io, json, os, sys, time, urllib.request

SOURCES = ["22Na", "54Mn", "56Co", "57Co", "60Co", "65Zn", "88Y", "109Cd", "133Ba", "137Cs",
           "139Ce", "152Eu", "207Bi", "241Am", "113Sn", "85Sr", "51Cr", "46Sc", "182Ta", "166mHo"]
API = "https://nds.iaea.org/relnsd/v1/data?fields=decay_rads&nuclides={}&rad_types={}"
MIN_INTENSITY = 0.05   # % per decay; weaker lines are dropped
MIN_ENERGY = 10.0      # keV

def fetch(nuclide, rad, raw_dir, offline):
    path = os.path.join(raw_dir, f"{nuclide}_{rad}.csv")
    if not offline:
        api_name = nuclide.lower().replace("mho", "ho")       # isomers are rows of the ground-state query
        req = urllib.request.Request(API.format(api_name, rad),
                                     headers={"User-Agent": "Gamow-toolkit/0.1"})
        with urllib.request.urlopen(req, timeout=30) as r:
            text = r.read().decode()
        with open(path, "w") as f:
            f.write(text)
        time.sleep(0.3)
    with open(path) as f:
        return list(csv.DictReader(io.StringIO(f.read())))

def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None

def main():
    raw_dir, dst = sys.argv[1], sys.argv[2]
    offline = "--offline" in sys.argv
    os.makedirs(raw_dir, exist_ok=True)
    out = []
    for name in SOURCES:
        isomer = name.endswith("Ho") and "m" in name
        lines = []
        parent_energy = None
        # The "g" query returns every photon: gamma rays (from a nuclear level), X rays and annihilation.
        for r in fetch(name, "g", raw_dir, offline):
            pe = num(r.get("p_energy")) or 0.0
            if (pe > 1.0) != isomer:           # ground-state parent, unless the source is an isomer
                continue
            parent_energy = pe
            e, i, di = num(r.get("energy")), num(r.get("intensity")), num(r.get("unc_i"))
            if e is None or i is None or e < MIN_ENERGY or i < MIN_INTENSITY:
                continue
            from_level = (r.get("start_level_energy") or "").strip() != ""
            kind = "gamma" if from_level else ("annihilation" if abs(e - 511) < 1 else "xray")
            lines.append({"e": e, "i": i, "di": di or 0.0, "kind": kind})
        lines.sort(key=lambda l: l["e"])
        out.append({"nuclide": name, "parentLevel": parent_energy or 0.0, "lines": lines})
        print(f"{name}: {len(lines)} lines")
    with open(dst, "w") as f:
        json.dump({"source": "IAEA LiveChart of Nuclides API (ENSDF), intensities in % per decay",
                   "sources": out}, f, indent=1)

if __name__ == "__main__":
    main()
