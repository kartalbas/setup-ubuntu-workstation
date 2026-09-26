# Managed by setup-ubuntu-workstation: Windows Terminal behaviour kitty has no
# built-in action for, used by kitty.conf:
#   copy_or_paste     right click: copy the selection (and clear it), else paste
#   resize DIRECTION  Alt+Shift+Arrow: move the pane divider in that direction
from kittens.tui.handler import result_handler
from kitty.clipboard import get_clipboard_string


def main(args):
    pass


def copy_or_paste(window):
    if window.has_selection():
        window.copy_to_clipboard()
        window.clear_selection()
        return
    send_paste_event = getattr(window, 'send_paste_event', None)
    if send_paste_event is not None and send_paste_event():
        return
    text = get_clipboard_string()
    if text:
        window.paste_with_actions(text)


def resize(window, direction):
    tab = window.tabref()
    if tab is None:
        return
    edge = {'left': 'left', 'right': 'right', 'up': 'top', 'down': 'bottom'}[direction]
    # With a neighbour on that side the divider is our edge there: moving it
    # that way grows us; otherwise it is the opposite edge and we shrink.
    grow = bool(tab.current_layout.neighbors_for_window(window, tab.windows).get(edge))
    if direction in ('left', 'right'):
        tab.resize_window('wider' if grow else 'narrower', 3)
    else:
        tab.resize_window('taller' if grow else 'shorter', 3)


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    if args[1] == 'copy_or_paste':
        copy_or_paste(window)
    elif args[1] == 'resize':
        resize(window, args[2])
