"""Convert the SRIM-2013 data files (as shipped with LunaSRIM) into the compact files bundled
with NucPhysKit, and the SRModule.exe reference outputs into a test fixture.

Usage: python3 Tools/convert_srim.py Data/SRIM2013 \
           Packages/NucToolkit/Sources/NucPhysKit/Resources \
           Packages/NucToolkit/Tests/NucPhysKitTests/Resources

Outputs
  srim_scoef.csv        Z,symbol,c2..c93   (column numbers of SCOEF03.DAT, see SRIMData.swift)
  srim_snuc.csv         Z1,Z2,b1,b2,b3,b4  (pair nuclear stopping fit, Z1 <= Z2)
  srim_compounds.json   SRIM's compound dictionary: category, title, name, density, gas, [[Z, atom fraction]]
  srim_reference.json   (tests) the SR.IN inputs and the SRModule.exe output rows
"""
import json
import os
import re
import shlex
import sys

src, res, test_res = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(res, exist_ok=True)
os.makedirs(test_res, exist_ok=True)


def read(name):
    with open(os.path.join(src, name), "rb") as fh:
        return fh.read().decode("latin-1").replace("\r\n", "\n").split("\n")


# ---------------------------------------------------------------- SCOEF03.DAT
scoef = {}
for line in read("SCOEF03.DAT"):
    t = shlex.split(line)
    if len(t) < 95:
        continue
    sym, nums = t[0].strip(), [float(x) for x in t[2:95]]
    z = int(nums[0])
    scoef[z] = (sym, nums)
assert sorted(scoef) == list(range(1, 93)), "expected Z = 1..92"
with open(os.path.join(res, "srim_scoef.csv"), "w") as f:
    f.write("# SRIM-2013 SCOEF03.DAT, columns 2..93 after Z and symbol\n")
    for z in range(1, 93):
        sym, nums = scoef[z]
        f.write(",".join([str(z), sym] + [repr(v) for v in nums[1:]]) + "\n")

# ---------------------------------------------------------------- SNUC03.dat
pairs = {}
for line in read("SNUC03.dat"):
    t = line.split()
    if len(t) < 6:
        continue
    z1, z2 = int(t[0]), int(t[1])
    pairs[(min(z1, z2), max(z1, z2))] = [float(x) for x in t[2:6]]
with open(os.path.join(res, "srim_snuc.csv"), "w") as f:
    f.write("# SRIM-2013 SNUC03.dat: Z1,Z2,b1..b4 (symmetric in Z1, Z2)\n")
    for (z1, z2), c in sorted(pairs.items()):
        f.write(",".join([str(z1), str(z2)] + [repr(v) for v in c]) + "\n")

# ---------------------------------------------------------------- ATOMDATA (natural weights)
natural = {}
for line in read("ATOMDATA"):
    t = line.split()
    if len(t) >= 11 and t[0].isdigit():
        natural[int(t[0])] = float(t[5])

# ---------------------------------------------------------------- Compound.dat
def category(line):
    if "\xdf" not in line:            # section titles are framed with this character
        return None
    text = re.sub(r"[^A-Za-z0-9/ ,()&.-]", " ", line[1:]).strip()
    text = re.sub(r"\s+", " ", text)
    if not text or any(w in text for w in ("Density", "Name", "Stoich", "g/cm3")):
        return None
    text = text.split(" from ")[0].split("(9")[0].strip()
    return text.title().replace("(Misc.)", "(misc.)")


def csv_fields(line):
    out, cur, quoted = [], "", False
    for ch in line:
        if ch == '"':
            quoted = not quoted
        elif ch == "," and not quoted:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    out.append(cur.strip())
    return out


lines = read("Compound.dat")
compounds, cat, i = [], "Compounds", 0
while i < len(lines):
    l = lines[i]
    if l.startswith("!"):
        c = category(l)
        if c:
            cat = c
    elif l.startswith("*") and i + 1 < len(lines):
        title = re.split(r"\s{2,}", l[1:].strip())[0]
        gas = "(gas)" in l.lower()
        try:
            row = csv_fields(lines[i + 1])
            name, density, n = row[0], float(row[1]), int(float(row[2]))
            vals = [float(x) for x in row[3:3 + 2 * n] if x]
            if len(vals) < 2 * n:
                raise ValueError(name)
        except (ValueError, IndexError):
            i += 1
            continue
        mass_pc = name.startswith("%")
        els = []
        for k in range(n):
            z, amount = int(vals[2 * k]), vals[2 * k + 1]
            if mass_pc:
                amount /= natural[z]
            els.append((z, amount))
        tot = sum(a for _, a in els) or 1.0
        els = [[z, round(a / tot, 8)] for z, a in els if a > 0]
        compounds.append({"category": cat, "title": title, "name": name.lstrip("%"),
                          "density": density, "gas": gas or density < 0.01, "elements": els})
        i += 1
    i += 1
with open(os.path.join(res, "srim_compounds.json"), "w") as f:
    json.dump(compounds, f, separators=(",", ":"))

# ---------------------------------------------------------------- SRModule.exe references
ENERGY = {"eV": 1e-3, "keV": 1.0, "MeV": 1e3, "GeV": 1e6}
LENGTH = {"A": 1.0, "um": 1e4, "mm": 1e7, "m": 1e10, "km": 1e13}


def parse_input(path):
    with open(path, encoding="latin-1") as fh:
        rows = [l.strip() for l in fh if not l.startswith("---")]
    out = rows[0].strip('"')
    z1, m1 = rows[1].split()
    phase, density, corr = rows[2].split()
    n = int(rows[3])
    els = []
    for r in rows[4:4 + n]:
        t = shlex.split(r)
        els.append({"z": int(t[0]), "stoich": float(t[2]), "mass": float(t[3])})
    units = int(rows[4 + n])
    emin, emax = (float(x) for x in rows[5 + n].split())
    energies = []
    if emin == 0 and emax == 0:
        for r in rows[6 + n:]:
            if not r:
                continue
            if float(r) == 0:
                break
            energies.append(float(r))
    return out, {"ionZ": int(z1), "ionMass": float(m1), "gas": phase == "1",
                 "density": float(density), "correction": float(corr), "elements": els,
                 "units": units, "emin": emin, "emax": emax, "list": energies}


cases = {}
ref_dir = os.path.join(src, "reference_sr")
for case in sorted(os.listdir(ref_dir)):
    d = os.path.join(ref_dir, case)
    if not os.path.isdir(d):
        continue
    out, inp = parse_input(os.path.join(d, "SR.IN"))
    path = os.path.join(d, out)
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        continue                          # SRModule.exe stopped with a run-time error
    with open(path, encoding="latin-1") as fh:
        text = fh.read().replace("\r\n", "\n").split("\n")
    rows = []
    if inp["list"]:
        for l in text:
            t = l.split()
            if len(t) == 3:
                try:
                    rows.append([float(t[0]), float(t[1]), float(t[2])])
                except ValueError:
                    pass
    else:
        pat = re.compile(r"^\s*([\d.]+)\s+(eV|keV|MeV|GeV)\s+([\d.E+-]+)\s+([\d.E+-]+)\s+"
                         r"([\d.]+)\s+(A|um|mm|m|km)\s+([\d.]+)\s+(A|um|mm|m|km)\s+([\d.]+)\s+(A|um|mm|m|km)")
        for l in text:
            m = pat.match(l)
            if m:
                g = m.groups()
                rows.append([float(g[0]) * ENERGY[g[1]], float(g[2]), float(g[3]),
                             float(g[4]) * LENGTH[g[5]], float(g[6]) * LENGTH[g[7]],
                             float(g[8]) * LENGTH[g[9]]])
    if rows:
        inp["rows"] = rows
        cases[case] = inp
with open(os.path.join(test_res, "srim_reference.json"), "w") as f:
    json.dump(cases, f, indent=1)

print(f"{len(scoef)} elements, {len(pairs)} nuclear pairs, {len(compounds)} compounds, "
      f"{len(cases)} reference cases ({sum(1 for c in cases.values() if c['list'])} list mode)")
