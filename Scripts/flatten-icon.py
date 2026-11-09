"""The iPhone icon is the desktop's (paragon repo, build/icon.png) laid on
its own dark colour: iOS rounds the corners itself and refuses transparency.
python3 Scripts/flatten-icon.py <paragon>/build/icon.png"""
import struct, sys, zlib

src, out = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "Paragon/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
data = open(src, "rb").read()
assert data[:8] == b"\x89PNG\r\n\x1a\n"
pos, idat, w = 8, b"", 0
while pos < len(data):
    n, t = struct.unpack(">I4s", data[pos:pos + 8]); body = data[pos + 8:pos + 8 + n]; pos += 12 + n
    if t == b"IHDR":
        w, h, depth, ctype = struct.unpack(">IIBB", body[:10]); assert depth == 8 and ctype == 6, "RGBA 8-bit only"
    elif t == b"IDAT": idat += body
raw, bpp, stride = zlib.decompress(idat), 4, w * 4
rows, prev, i = [], bytearray(stride), 0
for _ in range(h):
    f, line = raw[i], bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
    for x in range(stride):
        a = line[x - bpp] if x >= bpp else 0; b = prev[x]; c = prev[x - bpp] if x >= bpp else 0
        if f == 1: line[x] = (line[x] + a) & 255
        elif f == 2: line[x] = (line[x] + b) & 255
        elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
        elif f == 4:
            p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    rows.append(line); prev = line
bg = rows[h // 2][8:11]  # the icon's own dark colour, from its left edge
outrows = b""
for line in rows:
    o = bytearray(b"\x00")
    for x in range(w):
        r, g, b_, a = line[x * 4:x * 4 + 4]
        o += bytes(int(bg[k] + ((r, g, b_)[k] - bg[k]) * a / 255) for k in range(3))
    outrows += o
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
open(out, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(outrows, 9)) + chunk(b"IEND", b""))
print("wrote", out, "background", bytes(bg).hex())
