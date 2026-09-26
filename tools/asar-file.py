#!/usr/bin/env python3
# asar-file.py ARCHIVE PATH — print one file from an Electron .asar archive
# (e.g. an app's icon) to stdout.
import json
import struct
import sys

archive, path = sys.argv[1], sys.argv[2].strip('/')
with open(archive, 'rb') as f:
    f.read(4)
    header_size, = struct.unpack('<I', f.read(4))
    f.read(4)
    json_size, = struct.unpack('<I', f.read(4))
    node = json.loads(f.read(json_size))
    for part in path.split('/'):
        node = node.get('files', {}).get(part) or sys.exit(f'{path}: not in {archive}')
    if 'offset' not in node:
        sys.exit(f'{path}: not a packed file in {archive}')
    f.seek(8 + header_size + int(node['offset']))
    sys.stdout.buffer.write(f.read(node['size']))
