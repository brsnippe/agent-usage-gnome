#!/usr/bin/env python3
"""What the running Cinnamon says about the applet, through its Looking Glass
D-Bus interface (the one Cinnamon's own debugging tool uses).

  cinnamon-state.py status    "Loaded", "Error", ... or "not loaded"
  cinnamon-state.py log       Cinnamon's log lines that mention the applet
  cinnamon-state.py eval CODE run JavaScript inside Cinnamon (tests only)

Exits 1 when Cinnamon can't be reached.
"""

import sys

from gi.repository import Gio, GLib

UUID = "agent-usage@local"


def call(method, parameters=None):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    return bus.call_sync(
        "org.Cinnamon.LookingGlass", "/org/Cinnamon/LookingGlass", "org.Cinnamon.LookingGlass",
        method, parameters, None, Gio.DBusCallFlags.NONE, 5000, None).unpack()


# Cinnamon's own status words are translated, so this goes by its error flag.
def status():
    ok, xlets = call("GetExtensionList")
    found = [xlet for xlet in xlets if xlet.get("uuid") == UUID] if ok else []
    if not found:
        return "not loaded"
    xlet = found[0]
    if xlet.get("error") == "true":
        return f"{xlet.get('status', 'error')}: {xlet.get('error_message', '')}"
    return "Loaded"


def log():
    ok, entries = call("GetErrorStack")
    return [f"{entry.get('category', '?')}: {entry.get('message', '')}"
            for entry in (entries if ok else []) if "agent-usage" in entry.get("message", "")]


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if command == "status":
            print(status())
        elif command == "log":
            print("\n".join(log()))
        elif command == "eval" and len(sys.argv) == 3:
            call("Eval", GLib.Variant("(s)", (sys.argv[2],)))
            ok, results = call("GetResults")
            print(results[-1].get("object", "") if ok and results else "")
        else:
            print(__doc__.strip(), file=sys.stderr)
            return 2
    except GLib.Error as error:
        print(f"cinnamon-state: can't reach Cinnamon: {error.message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
