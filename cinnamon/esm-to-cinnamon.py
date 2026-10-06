#!/usr/bin/env python3
"""Turn one of the panel's ES modules into a module Cinnamon can load.

Cinnamon loads an applet's code with its older module system. Cinnamon 6.0
to 6.6 evaluate each file with require() in scope and export its top-level
names; 6.8 imports it natively, which exports only `var` and `function`
declarations. Neither understands `import` or `export`.

The shared modules (usage.js, panel.js, ...) stay ES modules, which GNOME
and the tests use as they are. This rewrites the few forms they use:

  import Gio from 'gi://Gio';              const Gio = imports.gi.Gio;
  import * as Usage from './usage.js';     const Usage = _load('usage');
  import {isNewer} from './versions.js';   const {isNewer} = _load('versions');
  export function f(...)                   function f(...)
  export const X = ...                     var X = ...
  export class C {                         var C = class C {
  }                                        };

Anything else that imports or exports is refused, so a new form fails when
the applet is built rather than in the panel.

Usage: esm-to-cinnamon.py module.js > converted.js
"""

import os
import re
import sys

LOADER = """\
// Cinnamon 6.8 imports an applet's own modules through its extension
// object; 6.0 to 6.6 through require().
function _load(name) {
    const me = imports.ui.extension.getCurrentExtension?.();
    return me?.imports ? me.imports[name] : require(`./${name}`);
}
"""

GI_IMPORT = re.compile(r"import (\w+) from 'gi://(\w+)';")
NAMESPACE_IMPORT = re.compile(r"import \* as (\w+) from '\./([\w-]+)\.js';")
NAMED_IMPORT = re.compile(r"import (\{[\w\s,]+\}) from '\./([\w-]+)\.js';")
EXPORT_CONST = re.compile(r"export const (\w+) =")
EXPORT_CLASS = re.compile(r"export class (\w+)\b")
# What only an ES module may say, wherever it is.
MODULE_ONLY = re.compile(r"^(import|export)\b|\bimport\s*\(|\bimport\.meta\b")


class ConversionError(Exception):
    pass


def convert(source, name="module.js"):
    body = []
    modules = []
    open_class = None
    for number, line in enumerate(source.split("\n"), 1):
        def refuse(why):
            raise ConversionError(f"{name}:{number}: {why}: {line.strip()}")

        if open_class and line == "}":
            body.append("};")
            open_class = None
            continue
        if match := GI_IMPORT.fullmatch(line):
            body.append(f"const {match[1]} = imports.gi.{match[2]};")
        elif match := NAMESPACE_IMPORT.fullmatch(line) or NAMED_IMPORT.fullmatch(line):
            body.append(f"const {match[1]} = _load('{match[2]}');")
            modules.append(match[2])
        elif line.startswith("export function "):
            body.append(line[len("export "):])
        elif match := EXPORT_CONST.match(line):
            body.append("var" + line[len("export const"):])
        elif match := EXPORT_CLASS.match(line):
            if open_class:
                refuse(f"class {open_class} isn't closed by a '}}' on its own line")
            body.append(f"var {match[1]} = class{line[len('export class'):]}")
            open_class = match[1]
        elif MODULE_ONLY.search(line):
            refuse("can't convert this for Cinnamon")
        else:
            body.append(line)
    if open_class:
        raise ConversionError(f"{name}: class {open_class} isn't closed by a '}}' on its own line")

    header = [
        "'use strict';",
        f"// Generated from agent-usage@local/{name} by cinnamon/esm-to-cinnamon.py",
        "// when the applet was installed. Edit the original instead.",
        "",
    ]
    if modules:
        header += [LOADER]
    return "\n".join(header + body), modules


def main():
    if len(sys.argv) != 2:
        print("usage: esm-to-cinnamon.py module.js > converted.js", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as source:
        text = source.read()
    try:
        converted, _ = convert(text, os.path.basename(path))
    except ConversionError as error:
        print(f"esm-to-cinnamon: {error}", file=sys.stderr)
        return 1
    sys.stdout.write(converted)
    return 0


if __name__ == "__main__":
    sys.exit(main())
