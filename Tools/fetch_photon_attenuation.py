"""Bundle NIST elemental total mass attenuation (not energy absorption).

Run with --download to refresh the cached source pages, otherwise build offline.
Preserve duplicate energies: they describe the two sides of absorption edges.
"""
import concurrent.futures
from decimal import Decimal
import json
from pathlib import Path
import re
import sys
import urllib.request

root = Path(__file__).resolve().parents[1]
cache = root / "Data/NIST"
cache.mkdir(exist_ok=True)


def element(z):
    path = cache / f"z{z:02}.html"
    if "--download" in sys.argv:
        url = f"https://pml.nist.gov/PhysRefData/XrayMassCoef/ElemTab/z{z:02}.html"
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=60) as response:
            path.write_bytes(response.read())
    page = path.read_text()
    block = re.search(r"<PRE>(.*?)</PRE>", page, re.S | re.I).group(1)
    rows = re.findall(r"(\d\.\d+E[+-]\d+)\s+(\d\.\d+E[+-]\d+)\s+(\d\.\d+E[+-]\d+)", block)
    points = [[float(Decimal(e) * 1000), float(mu)] for e, mu, _ in rows]
    assert len(points) >= 30 and points[0][0] == 1 and points[-1][0] == 20000, z
    assert all(a[0] <= b[0] for a, b in zip(points, points[1:])), z
    return str(z), points


with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    tables = dict(pool.map(element, range(1, 93)))
output = root / "Packages/NucToolkit/Sources/NucPhysKit/Resources/photon_attenuation.json"
output.write_text(json.dumps(tables, separators=(",", ":")) + "\n")
print(f"Wrote {len(tables)} elements to {output}")
