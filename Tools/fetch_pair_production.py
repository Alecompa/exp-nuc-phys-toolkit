"""Bundle NIST XCOM pair-production and total attenuation for γ-detector elements, 1.022-20 MeV.

Used to scale the single/double escape peak ratios with energy. Run with --download to refresh
the cached XCOM pages under Data/NIST/xcom, otherwise build offline.
Columns kept per row: energy (keV), pair production (nuclear + electron field), total with coherent, cm²/g.
"""
import json
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request

root = Path(__file__).resolve().parents[1]
cache = root / "Data/NIST/xcom"
cache.mkdir(parents=True, exist_ok=True)
# Ge (HPGe), Na + I (NaI), La + Br (LaBr3), Bi + Ge + O (BGO), Cs + I (CsI), Si.
elements = [8, 11, 14, 32, 35, 53, 55, 57, 83]
energies = [1.022, 1.05, 1.1, 1.2, 1.3, 1.5, 1.75, 2, 2.25, 2.5, 3, 3.5, 4, 4.5, 5, 6, 7, 8, 9, 10,
            11, 12, 13, 14, 15, 16, 18, 20]


def element(z):
    path = cache / f"z{z:02}.html"
    if "--download" in sys.argv:
        data = urllib.parse.urlencode({
            "ZNum": z, "OutOpt": "PIC", "Graph6": "on", "NumAdd": 1,
            "Energies": "\r\n".join(str(e) for e in energies), "Output": "on",
            "WindowXmin": 0.001, "WindowXmax": 100000, "ResizeFlag": "on"}).encode()
        request = urllib.request.Request("https://physics.nist.gov/cgi-bin/Xcom/xcom3_1", data=data,
                                         headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=60) as response:
            path.write_bytes(response.read())
    text = re.sub(r"<[^>]*>", " ", path.read_text())
    number = r"(\d\.\d+E[+-]\d+)"
    rows = {}
    for line in text.splitlines():
        m = re.match(r"\s*" + r"\s+".join([number] * 8) + r"\s*$", line)
        if not m:
            continue
        e, _, _, _, nuc, ele, total, _ = (float(x) for x in m.groups())
        if 1.022 <= e <= 20.0001:
            rows[round(e * 1000, 3)] = [round(e * 1000, 3), nuc + ele, total]
    points = [rows[k] for k in sorted(rows)]
    assert points[0][0] == 1022 and points[-1][0] == 20000 and len(points) >= len(energies), z
    return str(z), points


tables = dict(element(z) for z in elements)
output = root / "Packages/NucToolkit/Sources/NucPhysKit/Resources/pair_production.json"
output.write_text(json.dumps(tables, separators=(",", ":")) + "\n")
print(f"Wrote {len(tables)} elements to {output}")
