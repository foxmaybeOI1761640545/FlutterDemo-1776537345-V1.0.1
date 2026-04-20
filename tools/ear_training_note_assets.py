#!/usr/bin/env python3
"""Generate and verify fixed-pitch ear-training WAV assets.

The note set uses 12-TET with A4 = 440Hz and C-major degrees in octave 5:
Do(C5), Re(D5), Mi(E5), Fa(F5), Sol(G5), La(A5), Ti(B5).
"""

from __future__ import annotations

import argparse
import math
import sys
import wave
from array import array
from pathlib import Path

SAMPLE_RATE = 44_100
DURATION_SECONDS = 0.55
ATTACK_SECONDS = 0.008
RELEASE_SECONDS = 0.06
AMPLITUDE = 0.85

# Equal temperament reference frequencies (A4 = 440Hz).
NOTE_SPECS: dict[str, tuple[str, float]] = {
    "Do": ("ear-note-do.wav", 523.2511306011972),  # C5
    "Re": ("ear-note-re.wav", 587.3295358348151),  # D5
    "Mi": ("ear-note-mi.wav", 659.2551138257398),  # E5
    "Fa": ("ear-note-fa.wav", 698.4564628660078),  # F5
    "Sol": ("ear-note-sol.wav", 783.9908719634985),  # G5
    "La": ("ear-note-la.wav", 880.0),  # A5
    "Ti": ("ear-note-ti.wav", 987.7666025122483),  # B5
}


def _make_note_samples(frequency_hz: float) -> bytes:
    total_samples = int(round(SAMPLE_RATE * DURATION_SECONDS))
    attack_samples = max(1, int(round(SAMPLE_RATE * ATTACK_SECONDS)))
    release_samples = max(1, int(round(SAMPLE_RATE * RELEASE_SECONDS)))
    frames = bytearray()

    for i in range(total_samples):
        if i < attack_samples:
            envelope = i / attack_samples
        elif i > total_samples - release_samples:
            envelope = max(0.0, (total_samples - i) / release_samples)
        else:
            envelope = 1.0

        t = i / SAMPLE_RATE
        sample = AMPLITUDE * envelope * math.sin(2.0 * math.pi * frequency_hz * t)
        quantized = int(max(-32767, min(32767, round(sample * 32767))))
        frames.extend(quantized.to_bytes(2, byteorder="little", signed=True))

    return bytes(frames)


def generate_assets(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for degree, (filename, frequency_hz) in NOTE_SPECS.items():
        path = output_dir / filename
        samples = _make_note_samples(frequency_hz)
        with wave.open(str(path), "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(SAMPLE_RATE)
            wav_file.writeframes(samples)
        print(f"generated {degree:<3} {path} @ {frequency_hz:.6f}Hz")


def _read_wav_as_floats(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as wav_file:
        channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        sample_rate = wav_file.getframerate()
        frame_count = wav_file.getnframes()
        raw_frames = wav_file.readframes(frame_count)

    if channels != 1 or sample_width != 2:
        raise ValueError(f"{path}: expected mono 16-bit PCM WAV.")

    int_samples = array("h")
    int_samples.frombytes(raw_frames)
    if sys.byteorder == "big":
        int_samples.byteswap()

    return [sample / 32768.0 for sample in int_samples], sample_rate


def _estimate_frequency_autocorrelation(
    samples: list[float],
    sample_rate: int,
    min_frequency_hz: float,
    max_frequency_hz: float,
) -> float:
    start = int(sample_rate * 0.08)
    end = min(len(samples), start + int(sample_rate * 0.35))
    if end - start < 256:
        raise ValueError("audio sample is too short for reliable frequency estimation.")

    segment = samples[start:end]
    mean = sum(segment) / len(segment)
    centered = [sample - mean for sample in segment]

    min_lag = max(2, int(sample_rate / max_frequency_hz))
    max_lag = min(len(centered) - 2, int(sample_rate / min_frequency_hz))
    if max_lag <= min_lag:
        raise ValueError("invalid lag search range for frequency estimation.")

    def correlation(lag: int) -> float:
        total = 0.0
        upper = len(centered) - lag
        for i in range(upper):
            total += centered[i] * centered[i + lag]
        return total

    corr_values: dict[int, float] = {}
    best_lag = min_lag
    best_value = float("-inf")
    for lag in range(min_lag, max_lag + 1):
        value = correlation(lag)
        corr_values[lag] = value
        if value > best_value:
            best_value = value
            best_lag = lag

    prev_value = corr_values.get(best_lag - 1, best_value)
    next_value = corr_values.get(best_lag + 1, best_value)
    denominator = prev_value - (2.0 * best_value) + next_value
    if denominator == 0.0:
        delta = 0.0
    else:
        delta = 0.5 * (prev_value - next_value) / denominator
    delta = max(-1.0, min(1.0, delta))
    refined_lag = best_lag + delta

    return sample_rate / refined_lag


def verify_assets(output_dir: Path, max_cents_error: float) -> int:
    failures = 0
    for degree, (filename, target_hz) in NOTE_SPECS.items():
        path = output_dir / filename
        if not path.exists():
            print(f"missing  {degree:<3} {path}")
            failures += 1
            continue

        samples, sample_rate = _read_wav_as_floats(path)
        estimated_hz = _estimate_frequency_autocorrelation(
            samples=samples,
            sample_rate=sample_rate,
            min_frequency_hz=target_hz * 0.85,
            max_frequency_hz=target_hz * 1.15,
        )
        cents_error = 1200.0 * math.log2(estimated_hz / target_hz)
        within = abs(cents_error) <= max_cents_error
        status = "ok" if within else "fail"
        if not within:
            failures += 1
        print(
            f"{status:<4} {degree:<3} target={target_hz:9.4f}Hz "
            f"measured={estimated_hz:9.4f}Hz error={cents_error:+7.3f} cents"
        )

    if failures > 0:
        print(f"verification failed: {failures} note(s) exceed +/-{max_cents_error:.2f} cents.")
        return 1

    print(f"verification passed: all notes within +/-{max_cents_error:.2f} cents.")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        default="assets/audio",
        help="Directory where note WAV files are generated and verified.",
    )
    parser.add_argument(
        "--generate",
        action="store_true",
        help="Generate note WAV assets.",
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Run strict pitch verification on note WAV assets.",
    )
    parser.add_argument(
        "--max-cents",
        type=float,
        default=1.0,
        help="Maximum allowed absolute tuning error in cents for verification.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    run_generate = args.generate or (not args.generate and not args.verify)
    run_verify = args.verify or (not args.generate and not args.verify)

    if run_generate:
        generate_assets(output_dir)
    if run_verify:
        return verify_assets(output_dir, max_cents_error=args.max_cents)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
