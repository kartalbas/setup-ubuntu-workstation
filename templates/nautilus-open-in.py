# Managed by setup-ubuntu-workstation: "Open in ..." entries in the Files app
# (Nautilus) for the terminals and editors that are installed — on a folder,
# on the empty space of a folder, and (editors) on a single file.
# Run directly, it lists the entries the Files app shows (setup.sh doctor).
import os
import shutil

# No require_version: the Files app loads the Nautilus API version it speaks
# (4.1 in Nautilus 50), as the nautilus-python examples do.
from gi.repository import GLib, GObject, Nautilus

# label, program, command (the program's path, a path), folders only
ENTRIES = [
    ('kitty', 'kitty', lambda x, p: [x, '--directory', p], True),
    ('Ghostty', 'ghostty', lambda x, p: [x, '--gtk-single-instance=false', f'--working-directory={p}'], True),
    ('Terminal (Ptyxis)', 'ptyxis', lambda x, p: [x, '--new-window', f'--working-directory={p}'], True),
    ('VS Code', 'code', lambda x, p: [x, p], False),
    ('Antigravity IDE', 'antigravity-ide', lambda x, p: [x, p], False),
]

# Programs whose package brings its own "Open in" extension (in the system's
# extensions folder): while it is there, the menu shows only that one.
OWN_EXTENSIONS = {'ghostty': 'ghostty.py'}
EXTENSION_DIRS = ['/usr/share/nautilus-python/extensions',
                  os.path.expanduser('~/.local/share/nautilus-python/extensions')]
# Programs this setup installs live in ~/.local/bin, which the Files app's
# PATH may lack (it is added at login only when it existed then).
HOME_BIN = os.path.expanduser('~/.local/bin')


def find(program):
    return shutil.which(program) or shutil.which(program, path=HOME_BIN)


def brings_own(program):
    own = OWN_EXTENSIONS.get(program)
    return bool(own) and any(os.path.exists(os.path.join(d, own)) for d in EXTENSION_DIRS)


class OpenIn(GObject.GObject, Nautilus.MenuProvider):
    def _items(self, path, is_dir, where):
        items = []
        for label, program, command, folders_only in ENTRIES:
            exe = find(program)
            if (folders_only and not is_dir) or not exe or brings_own(program):
                continue
            item = Nautilus.MenuItem(name=f'SetupOpenIn::{program}::{where}', label=f'Open in {label}')
            item.connect('activate', self._run, command(exe, path))
            items.append(item)
        return items

    def _run(self, _item, argv):
        # GLib reaps the program itself, so the Files app keeps no zombie
        GLib.spawn_async(argv, working_directory=os.path.expanduser('~'),
                         flags=GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.STDOUT_TO_DEV_NULL
                         | GLib.SpawnFlags.STDERR_TO_DEV_NULL)

    def get_file_items(self, files):
        if len(files) != 1 or files[0].get_uri_scheme() != 'file':
            return []
        return self._items(files[0].get_location().get_path(), files[0].is_directory(), 'item')

    def get_background_items(self, folder):
        if folder.get_uri_scheme() != 'file':
            return []
        return self._items(folder.get_location().get_path(), True, 'background')


if __name__ == '__main__':
    print(', '.join(label + (' (its own extension)' if brings_own(program) else '')
                    for label, program, _, _ in ENTRIES if find(program)) or 'no program installed')
