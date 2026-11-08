"""Build the EXFOR index bundled with NucPhysKit from a file listing of IAEA-NDS/exfortables_py.

The app does not bundle EXFOR data. It bundles only the list of cross-section tables in exfortables_py at one
pinned commit, and downloads a table from raw.githubusercontent.com when the user opens it. Pinning the commit
keeps every link valid even when the repository reorganises its directories.

Kept: cross sections (observable `xs`) for p, d, t, 3He (h) and alpha projectiles and for the heavy-ion tree
(`ion/<target>/<projectile>/<channel>/xs`), on isotopic targets only (natural elements, mass 0, are skipped).

Output (text, compressed with raw DEFLATE so that Foundation's `.zlib` decompression reads it):
  #exfortables_py <commit> <commit date>
  @<directory before /xs/>            e.g. @p/Al-27/p-g
  <file name after /xs/>              one line per table, e.g. Al-27_p-g-L0_Al-27_D.R.Chakrabarty-D6305-002-0-2017.txt
The table's path in the repository is <directory>/xs/<file name>.

Get the listing without downloading the data (trees only, a few tens of MB):
  git clone --depth 1 --filter=blob:none --no-checkout https://github.com/IAEA-NDS/exfortables_py.git /tmp/xt
  git -C /tmp/xt ls-tree -r --name-only HEAD > /tmp/xt_paths.txt
  git -C /tmp/xt log -1 --format='%H %cs'
Usage:
  python3 -I Tools/build_exfor_index.py /tmp/xt_paths.txt <commit> <date> \
      Packages/NucToolkit/Sources/NucPhysKit/Resources/exfor_index.deflate
"""
import re, sys, zlib
from collections import defaultdict

PROJECTILES = {"p", "d", "t", "h", "a"}
# <author>-<entry>-<subentry>-<pointer>-<year>.txt; checked to hold for every table in the 2026-09-11 snapshot.
TAIL = re.compile(r"^.+-[0-9A-Z]{5}-\d{3}-[0-9A-Z]-\d{4}\.txt$")


def keep(path):
    head, sep, name = path.partition("/xs/")
    if not sep:
        return None
    parts = head.split("/")
    tree = parts[0]
    if tree in PROJECTILES and len(parts) == 3:
        target = parts[1]
    elif tree == "ion" and len(parts) == 4:
        target = parts[1]
        if parts[2].endswith("-0"):              # natural-element projectile
            return None
    else:
        return None
    if target.endswith("-0"):
        return None
    fields = name.split("_")
    if len(fields) not in (3, 4) or not TAIL.match(fields[-1]):
        raise ValueError(f"file name does not follow the exfortables grammar: {path}")
    return head, name


def main():
    src, commit, date, dst = sys.argv[1:5]
    groups = defaultdict(list)
    with open(src) as f:
        for line in f:
            k = keep(line.rstrip("\n"))
            if k:
                groups[k[0]].append(k[1])
    out = [f"#exfortables_py {commit} {date}"]
    for head in sorted(groups):
        out.append("@" + head)
        out.extend(sorted(groups[head]))
    text = ("\n".join(out) + "\n").encode()
    c = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw DEFLATE (no zlib header), as Apple's COMPRESSION_ZLIB
    blob = c.compress(text) + c.flush()
    with open(dst, "wb") as f:
        f.write(blob)
    n = sum(len(v) for v in groups.values())
    print(f"{n} tables in {len(groups)} directories; {len(text)} bytes of text, {len(blob)} bytes compressed")


if __name__ == "__main__":
    main()
