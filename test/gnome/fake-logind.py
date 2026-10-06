#!/usr/bin/env python3
"""Owns org.freedesktop.login1 on the system bus, so GNOME Shell starts in a
container, where there's no logind. GNOME Shell only needs the name to have
an owner; every call here fails politely, and nothing ever sleeps."""

from gi.repository import Gio, GLib

INTERFACE = """
<node>
  <interface name="org.freedesktop.login1.Manager">
    <method name="GetSession"><arg type="s" direction="in"/><arg type="o" direction="out"/></method>
    <method name="GetSessionByPID"><arg type="u" direction="in"/><arg type="o" direction="out"/></method>
    <method name="ListSessions"><arg type="a(susso)" direction="out"/></method>
    <method name="CanSuspend"><arg type="s" direction="out"/></method>
    <method name="CanRebootToBootLoaderMenu"><arg type="s" direction="out"/></method>
    <method name="Inhibit">
      <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
      <arg type="s" direction="in"/><arg type="h" direction="out"/>
    </method>
    <signal name="PrepareForSleep"><arg type="b"/></signal>
  </interface>
</node>"""


def on_call(_connection, _sender, _path, _interface, method, _parameters, invocation):
    if method == "ListSessions":
        invocation.return_value(GLib.Variant("(a(susso))", ([],)))
    elif method.startswith("Can"):
        invocation.return_value(GLib.Variant("(s)", ("na",)))
    else:
        invocation.return_dbus_error("org.freedesktop.login1.NoSuchSession", "There are no sessions in this container.")


def on_bus(connection, _name):
    interface = Gio.DBusNodeInfo.new_for_xml(INTERFACE).interfaces[0]
    connection.register_object("/org/freedesktop/login1", interface, on_call, None, None)


Gio.bus_own_name(Gio.BusType.SYSTEM, "org.freedesktop.login1", Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
