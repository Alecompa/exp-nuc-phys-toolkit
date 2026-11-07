"""Convert AME2020 mass_1.mas20.txt (fixed-width) into the compact CSV bundled with NucPhysKit.

Output columns: Z,A,symbol,mass_excess_keV,unc_keV,estimated
'estimated' = 1 when AME marks the value with '#' (non-experimental systematics).
Usage: python3 Tools/convert_ame2020.py Data/mass_1.mas20.txt Packages/NucToolkit/Sources/NucPhysKit/Resources/ame2020.csv
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
rows = []
with open(src) as f:
    for line in f:
        line = line.rstrip("\n")
        if len(line) < 54:
            continue
        try:
            n, z, a = int(line[4:9]), int(line[9:14]), int(line[14:19])
        except ValueError:
            continue
        el = line[20:23].strip()
        mass, unc = line[28:42].strip(), line[42:54].strip()
        if not el or "*" in mass:
            continue
        est = "#" in mass or "#" in unc
        # AME writes '#' in place of the decimal point for estimated values
        mass, unc = float(mass.replace("#", ".")), float(unc.replace("#", ".") or 0)
        assert n + z == a
        rows.append((z, a, el, mass, unc, int(est)))
with open(dst, "w") as f:
    f.write("Z,A,symbol,mass_excess_keV,unc_keV,estimated\n")
    for r in rows:
        f.write(f"{r[0]},{r[1]},{r[2]},{r[3]:.6f},{r[4]:.6f},{r[5]}\n")
print(len(rows), "nuclides written")
