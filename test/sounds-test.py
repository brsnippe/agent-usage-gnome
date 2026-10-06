#!/usr/bin/env python3
# Run with: python3 test/sounds-test.py
#
# The robot's sounds: the files in agent-usage@local/sounds are what
# scripts/make-sounds.py makes, in the format every platform plays, short and
# without a click at either end.

import importlib.util
import os
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("make_sounds", os.path.join(ROOT, "scripts", "make-sounds.py"))
make_sounds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_sounds)

failures = 0


def check(name, actual, expected):
    global failures
    ok = actual == expected
    if not ok:
        failures += 1
    print(f"{'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f"\n     got      {actual!r}\n     expected {expected!r}"))


check("there's a sound for each alert", sorted(make_sounds.SOUNDS), ["ready", "waiting"])
for name, notes in make_sounds.SOUNDS.items():
    path = os.path.join(ROOT, "agent-usage@local", "sounds", f"{name}.wav")
    with wave.open(path, "rb") as sound:
        shape = (sound.getnchannels(), sound.getsampwidth(), sound.getframerate(), sound.getcomptype())
        frames = sound.readframes(sound.getnframes())
    samples = [int.from_bytes(frames[i:i + 2], "little", signed=True) for i in range(0, len(frames), 2)]
    check(f"{name}.wav: 16-bit PCM, mono, 44.1 kHz", shape, (1, 2, 44100, "NONE"))
    # Another machine's maths library may round a sample the other way.
    expected = make_sounds.pcm(make_sounds.samples(notes))
    off = [abs(a - b) for a, b in zip(samples, expected)]
    check(f"{name}.wav: what scripts/make-sounds.py makes", (len(samples), max(off, default=0) <= 1), (len(expected), True))
    check(f"{name}.wav: under a second", len(samples) < make_sounds.RATE, True)
    check(f"{name}.wav: no louder than -6 dB", max(abs(s) for s in samples) <= 16384, True)
    check(f"{name}.wav: starts and ends silent", (abs(samples[0]) <= 1, abs(samples[-1]) <= 1), (True, True))

print("\nall passed" if failures == 0 else f"\n{failures} failed")
sys.exit(1 if failures else 0)
