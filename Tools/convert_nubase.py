"""Convert NUBASE2020 (nubase_4.mas20.txt, fixed width) into the CSV bundled with NucPhysKit.

Output columns:
  Z,A,state,excitation_keV,excitation_estimated,half_life_s,half_life_unc_s,half_life_text,jpi,decay,abundance
state: 0 ground state, 1.. isomers/levels in NUBASE order; half_life_s: -1 stable, empty when unknown.
half_life_text keeps NUBASE's value, unit and limits for display ("5.2714 y", ">2.2 Zy", "p-unst").
Usage: python3 -I Tools/convert_nubase.py Data/nubase_4.mas20.txt Packages/NucToolkit/Sources/NucPhysKit/Resources/nubase2020.csv
"""
import csv, math, sys

YEAR = 365.2422 * 86400
UNITS = {"ys": 1e-24, "zs": 1e-21, "as": 1e-18, "fs": 1e-15, "ps": 1e-12, "ns": 1e-9, "us": 1e-6, "ms": 1e-3,
         "s": 1.0, "m": 60.0, "h": 3600.0, "d": 86400.0, "y": YEAR, "ky": 1e3 * YEAR, "My": 1e6 * YEAR,
         "Gy": 1e9 * YEAR, "Ty": 1e12 * YEAR, "Py": 1e15 * YEAR, "Ey": 1e18 * YEAR, "Zy": 1e21 * YEAR,
         "Yy": 1e24 * YEAR}
WIDTH = {"eV": 1e-3, "keV": 1.0, "MeV": 1e3}       # widths in keV → T1/2 = ħ ln2 / Γ
HBAR_KEV_S = 6.582119569e-19

def to_float(s):
    try:
        return float(s.replace("#", "").strip())
    except ValueError:
        return None

def main():
    src, dst = sys.argv[1], sys.argv[2]
    rows = []
    with open(src) as f:
        for line in f:
            if line.startswith("#") or len(line) < 70:
                continue
            line = line.rstrip("\n").ljust(210)
            a, zi = int(line[0:3]), line[4:8]
            z, state = int(zi[:3]), int(zi[3])
            if state >= 8:                         # isobaric analogue states
                continue
            exc = line[42:54].strip()
            exc_val = to_float(exc) if exc else 0.0
            if exc and exc_val is None:            # non-numeric excitation (e.g. "non-exist")
                continue
            t, unit, dt = line[69:78].strip(), line[78:80].strip(), line[81:88].strip()
            hl, hl_unc, text = "", "", ""
            if t.startswith("stbl"):
                hl, text = "-1", "stable"
            elif t.startswith("p-unst"):
                text = "particle unstable"
            elif t:
                text = f"{t} {unit}".strip()
                v = to_float(t.lstrip("<>~"))
                u = to_float(dt.lstrip("<>~")) if dt and dt[0].isdigit() else None
                scale = None
                if unit in UNITS:
                    scale = UNITS[unit]
                if v is not None and scale is not None:
                    hl = f"{v * scale:.6e}"
                    if u is not None and not t[0] in "<>~":
                        hl_unc = f"{u * scale:.3e}"
                elif v is not None and unit in WIDTH and v > 0:
                    hl = f"{HBAR_KEV_S * math.log(2) / (v * WIDTH[unit]):.6e}"
                if t[0] in "<>~" or "#" in t:
                    text = text  # limits and systematics are shown as printed
            jpi = line[88:102].strip()
            br = line[119:209].strip()
            abundance = ""
            decays = []
            for part in br.split(";"):
                part = part.strip()
                if part.startswith("IS="):
                    abundance = part[3:].split()[0]
                elif part:
                    decays.append(part)
            rows.append([z, a, state, f"{exc_val:.4f}", int("#" in exc), hl, hl_unc, text, jpi,
                         ";".join(decays), abundance])
    with open(dst, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Z", "A", "state", "excitation_keV", "excitation_estimated", "half_life_s", "half_life_unc_s",
                    "half_life_text", "jpi", "decay", "abundance"])
        w.writerows(rows)
    print(len(rows), "states written")

if __name__ == "__main__":
    main()
