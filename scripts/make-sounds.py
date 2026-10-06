#!/usr/bin/env python3
"""Make the two sounds the robot plays when a session wants you.

  waiting.wav  a double blip: a session waits for you
  ready.wav    a rising chime: a session finished its turn

Made here from sine waves, so there's nothing to license, and the same every
time, so test/sounds-test.py can check the files in the repository are this
script's. 16-bit PCM mono WAV: what libcanberra (GNOME, Cinnamon) and macOS
all play.

Usage: scripts/make-sounds.py [DIR]    (default: agent-usage@local/sounds)
"""

import math
import os
import sys
import wave

RATE = 44100
# The loudest sample, as a fraction of full scale: about -6 dB.
PEAK = 0.5
# Overtones of each note: (multiple of its frequency, loudness).
PARTIALS = ((1, 1.0), (2, 0.28), (3, 0.08))
ATTACK = 0.006
FADE = 0.015

# Notes: (frequency in Hz, start and length in seconds, decay time constant).
SOUNDS = {
    # A5 twice, short.
    "waiting": [(880.0, 0.0, 0.11, 0.045), (880.0, 0.14, 0.13, 0.05)],
    # E5, then B5 ringing on.
    "ready": [(659.26, 0.0, 0.42, 0.11), (987.77, 0.11, 0.55, 0.16)],
}


def samples(notes):
    """The sound as floats, its loudest sample at PEAK."""
    length = max(start + duration for _, start, duration, _ in notes)
    buffer = [0.0] * int(round(length * RATE))
    for frequency, start, duration, decay in notes:
        first = int(round(start * RATE))
        count = int(round(duration * RATE))
        for n in range(count):
            t = n / RATE
            envelope = min(1.0, t / ATTACK) * math.exp(-t / decay)
            # Down to nothing at the end, so the note doesn't click off.
            envelope *= min(1.0, (duration - t) / FADE)
            value = sum(loudness * math.sin(2 * math.pi * frequency * multiple * t) for multiple, loudness in PARTIALS)
            buffer[first + n] += envelope * value
    loudest = max(abs(value) for value in buffer)
    return [value * PEAK / loudest for value in buffer]


def pcm(values):
    return [int(round(value * 32767)) for value in values]


def write(path, values):
    frames = b"".join(sample.to_bytes(2, "little", signed=True) for sample in pcm(values))
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    folder = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "agent-usage@local", "sounds")
    os.makedirs(folder, exist_ok=True)
    for name, notes in SOUNDS.items():
        path = os.path.join(folder, f"{name}.wav")
        write(path, samples(notes))
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
