"""Sums up an Instruments Time Profiler export (xctrace export ... table time-profile) into the functions the app
spends its time in: 'self' = the function that was running, 'total' = it or anything it called. Usage:
python3 profile.py tp.xml > profile.txt"""
import sys, collections, xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
byid = {}
for e in root.iter():
    i = e.get("id")
    if i is not None:
        byid[i] = e

def res(e):
    r = e.get("ref")
    return byid.get(r, e) if r is not None else e

selfc, total, selfall = collections.Counter(), collections.Counter(), collections.Counter()
rows = 0
for row in root.iter("row"):
    bt = None
    for c in row:
        if c.tag in ("backtrace", "tagged-backtrace"):
            bt = res(c)
            if bt.tag == "tagged-backtrace":
                inner = bt.find("backtrace")
                bt = res(inner) if inner is not None else bt
    if bt is None:
        continue
    frames = []
    for f in bt.iter("frame"):
        f = res(f)
        name = f.get("name") or "?"
        b = f.find("binary")
        bn = (res(b).get("name") if b is not None else "") or ""
        frames.append((name, bn))
    if not frames:
        continue
    rows += 1
    selfall[f"{frames[0][0]}  [{frames[0][1]}]"] += 1
    app = [n for n, b in frames if b.startswith("MacawP3")]   # Debug builds put the code in MacawP3.debug.dylib
    if app:
        selfc[app[0]] += 1
        for n in set(app):
            total[n] += 1

print(f"samples: {rows}\n")
print("== where the app's own code is running (first app function on the stack) ==")
for n, c in selfc.most_common(40):
    print(f"{100 * c / max(rows, 1):5.1f}%  {n}")
print("\n== app functions including everything they call ==")
for n, c in total.most_common(40):
    print(f"{100 * c / max(rows, 1):5.1f}%  {n}")
print("\n== the very top of the stack (any library) ==")
for n, c in selfall.most_common(40):
    print(f"{100 * c / max(rows, 1):5.1f}%  {n}")
