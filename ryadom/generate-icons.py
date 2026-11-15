"""Render the geometric Ryadom icon using only Python's standard library."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parent
BLUE = (49, 92, 219, 255)
WHITE = (255, 255, 255, 255)


def rounded(x, y, left, top, right, bottom, radius):
    if not (left <= x <= right and top <= y <= bottom):
        return False
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def pixel(x, y):
    color = (0, 0, 0, 0)
    shapes = [
        (0, 0, 256, 256, 56, BLUE),
        (38, 52, 184, 164, 19, WHITE),
        (48, 62, 174, 154, 9, BLUE),
        (106, 154, 116, 184, 5, WHITE),
        (78, 174, 136, 184, 5, WHITE),
        (125, 103, 217, 214, 19, WHITE),
        (135, 113, 207, 204, 9, BLUE),
        (151, 183, 191, 193, 5, WHITE),
    ]
    for left, top, right, bottom, radius, fill in shapes:
        if rounded(x, y, left, top, right, bottom, radius):
            color = fill
    return color


def png(size):
    rows = bytearray()
    scale = 256 / size
    for y in range(size):
        rows.append(0)
        for x in range(size):
            samples = [pixel((x + (sx + .5) / 4) * scale,
                             (y + (sy + .5) / 4) * scale)
                       for sy in range(4) for sx in range(4)]
            alpha = sum(c[3] for c in samples)
            rows.extend([round(sum(c[k] * c[3] for c in samples) / alpha)
                         if alpha else 0 for k in range(3)])
            rows.append(round(alpha / 16))

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack(
            '>I', zlib.crc32(kind + data))

    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack(
        '>IIBBBBB', size, size, 8, 6, 0, 0, 0)) +
        chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


if __name__ == '__main__':
    images = [(size, png(size)) for size in (16, 24, 32, 48, 64, 128, 256)]
    offset = 6 + 16 * len(images)
    directory = bytearray(struct.pack('<HHH', 0, 1, len(images)))
    for size, data in images:
        directory.extend(struct.pack('<BBBBHHII', size % 256, size % 256,
                                     0, 0, 1, 32, len(data), offset))
        offset += len(data)
    (ROOT / 'assets/ryadom.ico').write_bytes(
        bytes(directory) + b''.join(data for _, data in images))
    (ROOT / 'assets/ryadom.png').write_bytes(images[-1][1])
    (ROOT / 'ui/web/favicon.png').write_bytes(images[3][1])
