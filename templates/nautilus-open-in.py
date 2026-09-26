# Managed by setup-ubuntu-workstation: "Open in ..." entries in the Files app
# (Nautilus) for the terminals and editors that are installed — on a folder,
# on the empty space of a folder, and (editors) on a single file.
import os
import shutil
import subprocess

from gi import require_version
require_version('Nautilus', '4.0')
from gi.repository import GObject, Nautilus  # noqa: E402

# label, program, command for a path, folders only
ENTRIES = [
    ('kitty', 'kitty', lambda p: ['kitty', '--directory', p], True),
    ('Ghostty', 'ghostty', lambda p: ['ghostty', '--gtk-single-instance=false', f'--working-directory={p}'], True),
    ('Terminal (Ptyxis)', 'ptyxis', lambda p: ['ptyxis', '--new-window', f'--working-directory={p}'], True),
    ('VS Code', 'code', lambda p: ['code', p], False),
    ('Antigravity IDE', 'antigravity-ide', lambda p: ['antigravity-ide', p], False),
]


class OpenIn(GObject.GObject, Nautilus.MenuProvider):
    def _items(self, path, is_dir, where):
        items = []
        for label, program, command, folders_only in ENTRIES:
            if (folders_only and not is_dir) or not shutil.which(program):
                continue
            item = Nautilus.MenuItem(name=f'SetupOpenIn::{program}::{where}', label=f'Open in {label}')
            item.connect('activate', self._run, command(path))
            items.append(item)
        return items

    def _run(self, _item, argv):
        subprocess.Popen(argv, cwd=os.path.expanduser('~'), start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def get_file_items(self, files):
        if len(files) != 1 or files[0].get_uri_scheme() != 'file':
            return []
        return self._items(files[0].get_location().get_path(), files[0].is_directory(), 'item')

    def get_background_items(self, folder):
        if folder.get_uri_scheme() != 'file':
            return []
        return self._items(folder.get_location().get_path(), True, 'background')
