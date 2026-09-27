#!/bin/sh
# Managed by setup-ubuntu-workstation: Nemo's "Copy as path" — the full path of
# every selected item to the clipboard, one per line, as it is: no quotes and
# no newline after the last one, ready to paste anywhere.
[ "$#" -gt 0 ] || exit 0
{
  printf '%s' "$1"; shift
  for p in "$@"; do printf '\n%s' "$p"; done
} | wl-copy
