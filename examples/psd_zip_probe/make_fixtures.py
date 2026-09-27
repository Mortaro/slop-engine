"""Writes small PSDs with every channel compression PSD uses, and the checksum the reader must produce."""
import struct
import zlib
import os

WIDTH, HEIGHT = 37, 23
HERE = os.path.dirname(os.path.abspath(__file__))


def sample(channel, x, y, depth):
    value = (x * 7 + y * 13 + channel * 51) % 256
    if depth == 16:
        return value * 256 + (x * 3 + y) % 256
    return value


def plane_bytes(channel, depth):
    out = bytearray()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            v = sample(channel, x, y, depth)
            out += struct.pack('>H', v) if depth == 16 else bytes([v])
    return bytes(out)


def pack_bits(row):
    out = bytearray()
    i = 0
    while i < len(row):
        run = 1
        while i + run < len(row) and row[i + run] == row[i] and run < 128:
            run += 1
        if run > 1:
            out += bytes([257 - run, row[i]])
            i += run
        else:
            start = i
            while i < len(row) and (i + 1 >= len(row) or row[i + 1] != row[i]) and i - start < 128:
                i += 1
            out += bytes([i - start - 1]) + row[start:i]
    return bytes(out)


def encode(data, compression, depth):
    row_bytes = WIDTH * depth // 8
    rows = [data[r * row_bytes:(r + 1) * row_bytes] for r in range(HEIGHT)]
    if compression == 0:
        return data
    if compression == 1:
        packed = [pack_bits(r) for r in rows]
        return b''.join(struct.pack('>H', len(p)) for p in packed) + b''.join(packed)
    if compression == 2:
        return zlib.compress(data)
    predicted = bytearray()
    for r in rows:
        if depth == 16:
            values = [struct.unpack('>H', r[i:i + 2])[0] for i in range(0, len(r), 2)]
            deltas = [values[0]] + [(values[i] - values[i - 1]) % 65536 for i in range(1, len(values))]
            predicted += b''.join(struct.pack('>H', d) for d in deltas)
        else:
            predicted += bytes([r[0]] + [(r[i] - r[i - 1]) % 256 for i in range(1, len(r))])
    return zlib.compress(bytes(predicted))


def write_psd(path, compression, depth):
    channels = [0, 1, 2, -1]
    encoded = [encode(plane_bytes(3 if c == -1 else c, depth), compression, depth) for c in channels]
    record = struct.pack('>iiiiH', 0, 0, HEIGHT, WIDTH, len(channels))
    for c, e in zip(channels, encoded):
        record += struct.pack('>hI', c, len(e) + 2)
    name = b'probe'
    pascal = bytes([len(name)]) + name
    pascal += b'\0' * ((4 - len(pascal) % 4) % 4)
    extra = struct.pack('>II', 0, 0) + pascal
    record += b'8BIMnorm' + bytes([255, 0, 0, 0]) + struct.pack('>I', len(extra)) + extra
    channel_data = b''.join(struct.pack('>H', compression) + e for e in encoded)
    layer_info = struct.pack('>h', 1) + record + channel_data
    if len(layer_info) % 2:
        layer_info += b'\0'
    layer_and_mask = struct.pack('>I', len(layer_info)) + layer_info + struct.pack('>I', 0)
    merged = struct.pack('>H', 0) + b''.join(plane_bytes(c, depth) for c in [0, 1, 2, 3])
    header = b'8BPS' + struct.pack('>H', 1) + b'\0' * 6 + struct.pack('>HIIHH', 4, HEIGHT, WIDTH, depth, 3)
    body = header + struct.pack('>I', 0) + struct.pack('>I', 0) + struct.pack('>I', len(layer_and_mask)) + layer_and_mask + merged
    open(path, 'wb').write(body)


def checksum(depth):
    total = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            r, g, b, a = [sample(c, x, y, depth) for c in [0, 1, 2, 3]]
            if depth == 16:
                r, g, b, a = r >> 8, g >> 8, b >> 8, a >> 8
            value = (r + g * 256 + b * 65536 + a * 16777216) & 0xFFFFFFFF
            if value >= 1 << 31:
                value -= 1 << 32
            total += value
    return total


for depth in (8, 16):
    for compression in (0, 1, 2, 3):
        write_psd(os.path.join(HERE, 'fixtures', f'probe_{depth}_{compression}.psd'), compression, depth)
    print(depth, checksum(depth))
