#!/usr/bin/env python3
"""nemo-action-accel.py LAYOUT ACTION ACCELERATOR — give a Nemo action a
keyboard shortcut in Nemo's action layout (~/.config/nemo/actions-tree.json,
the file nemo-action-layout-editor writes).

Only added: when ACTION is in the layout already (anywhere, also in a
submenu), the user has placed it and it stays as it is; the rest of the file
is kept. Nemo appends every action the layout does not name, so a layout with
only this one hides nothing. A layout that is not valid JSON is left alone.
Exit code: 0 added or already there, 1 the layout could not be read.
"""
import json
import os
import sys


def names(items):
    for item in items:
        yield item.get("uuid")
        if isinstance(item.get("children"), list):
            yield from names(item["children"])


def main(path, action, accel):
    data = {"toplevel": []}
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            if not isinstance(data.get("toplevel"), list):
                raise ValueError("no 'toplevel' list")
        except (OSError, ValueError) as e:
            print(f"{path}: not changed, it cannot be read ({e})", file=sys.stderr)
            return 1
    if action in names(data["toplevel"]):
        return 0
    data["toplevel"].append({"uuid": action, "type": "action", "user-label": None,
                             "user-icon": None, "accelerator": accel})
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    print(f"{action}: {accel}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__.splitlines()[0])
    sys.exit(main(*sys.argv[1:]))
