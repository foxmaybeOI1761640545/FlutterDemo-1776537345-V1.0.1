#!/usr/bin/env python3
"""Generate and verify multi-octave piano-like ear-training WAV assets.

Asset naming:
  ear-piano-<degree><octave>.wav
Examples:
  ear-piano-do5.wav, ear-piano-sol4.wav, ear-piano-ti7.wav

The note set uses 12-TET with A4 = 440Hz and C-major scale degrees:
Do(C), Re(D), Mi(E), Fa(F), Sol(G), La(A), Ti(B).
"""

from __future__ import annotations

import argparse
import math
import sys
import wave
from array import array
from pathlib import Path

SAMPLE_RATE = 44_100
DURATION_SECONDS = 1.18
ATTACK_SECONDS = 0.006
RELEASE_SECONDS = 0.16
HAMMER_SECONDS = 0.022
TARGET_AMPLITUDE = 0.92

DEFAULT_MIN_OCTAVE = 3
DEFAULT_MAX_OCTAVE = 7

# degree_name, filename_slug, semitone offset from C
DEGREE_SPECS: tuple[tuple[str, str, int], ...] = (
    ("Do", "do", 0),
    ("Re", "re", 2),
    ("Mi", "mi", 4),
    ("Fa", "fa", 5),
    ("Sol", "sol", 7),
    ("La", "la", 9),
    ("Ti", "ti", 11),
)

# Harmonic profile tuned for a "soft piano-like" timbre.
PARTIALS: tuple[tuple[int, float, float], ...] = (
    (1, 1.00, 2.2),
    (2, 0.56, 3.0),
    (3, 0.33, 3.9),
    (4, 0.24, 4.8),
    (5, 0.16, 5.8),
    (6, 0.11, 6.9),
    (8, 0.07, 8.2),
)


def _midi_to_frequency(midi_note: int) -> float:
    return 440.0 * (2.0 ** ((midi_note - 69) / 12.0))


def _build_note_specs(
    min_octave: int,
    max_octave: int,
) -> dict[str, tuple[str, float]]:
    specs: dict[str, tuple[str, float]] = {}
    for octave in range(min_octave, max_octave + 1):
        c_midi = (octave + 1) * 12
        for degree, slug, semitone_from_c in DEGREE_SPECS:
            midi_note = c_midi + semitone_from_c
            frequency_hz = _midi_to_frequency(midi_note)
            filename = f"ear-piano-{slug}{octave}.wav"
            specs[f"{degree}{octave}"] = (filename, frequency_hz)
    return specs


def _make_piano_like_samples(frequency_hz: float) -> bytes:
    total_samples = int(round(SAMPLE_RATE * DURATION_SECONDS))
    attack_samples = max(1, int(round(SAMPLE_RATE * ATTACK_SECONDS)))
    release_samples = max(1, int(round(SAMPLE_RATE * RELEASE_SECONDS)))
    hammer_samples = max(1, int(round(SAMPLE_RATE * HAMMER_SECONDS)))
    nyquist = SAMPLE_RATE / 2.0

    float_samples: list[float] = []
    peak = 1e-12

    for i in range(total_samples):
        t = i / SAMPLE_RATE

        if i < attack_samples:
            attack_env = i / attack_samples
        else:
            attack_env = 1.0

        if i >= total_samples - release_samples:
            release_env = max(0.0, (total_samples - i) / release_samples)
        else:
            release_env = 1.0

        overall_decay = math.exp(-2.4 * t)
        envelope = attack_env * release_env * overall_decay

        sample = 0.0
        for harmonic, amplitude, decay_rate in PARTIALS:
            partial_freq = frequency_hz * harmonic
            if partial_freq >= nyquist * 0.96:
                continue
            phase = math.pi / (harmonic + 1.5)
            partial_decay = math.exp(-decay_rate * t)
            sample += (
                amplitude
                * partial_decay
                * math.sin((2.0 * math.pi * partial_freq * t) + phase)
            )

        if i < hammer_samples:
            hammer_progress = 1.0 - (i / hammer_samples)
            hammer = math.sin(2.0 * math.pi * frequency_hz * 6.4 * t)
            sample += 0.09 * hammer_progress * hammer

        sample *= envelope
        float_samples.append(sample)
        peak = max(peak, abs(sample))

    normalize = TARGET_AMPLITUDE / peak
    frames = bytearray()
    for sample in float_samples:
        quantized = int(max(-32767, min(32767, round(sample * normalize * 32767))))
        frames.extend(quantized.to_bytes(2, byteorder="little", signed=True))

    return bytes(frames)


def generate_assets(output_dir: Path, min_octave: int, max_octave: int) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    specs = _build_note_specs(min_octave=min_octave, max_octave=max_octave)
    for note_label, (filename, frequency_hz) in specs.items():
        path = output_dir / filename
        samples = _make_piano_like_samples(frequency_hz)
        with wave.open(str(path), "wb") as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(SAMPLE_RATE)
            wav_file.writeframes(samples)
        print(f"generated {note_label:<5} {path} @ {frequency_hz:9.4f}Hz")

    # Backward compatibility:
    # overwrite legacy single-octave filenames with octave-5 piano assets.
    legacy_octave = 5
    for degree, slug, _ in DEGREE_SPECS:
        key = f"{degree}{legacy_octave}"
        source_name = specs.get(key, (None, None))[0]
        if source_name is None:
            continue
        source_path = output_dir / source_name
        legacy_path = output_dir / f"ear-note-{slug}.wav"
        legacy_path.write_bytes(source_path.read_bytes())
        print(f"aliased {legacy_path} <= {source_path.name}")


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
    start = int(sample_rate * 0.05)
    end = min(len(samples), start + int(sample_rate * 0.32))
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


def verify_assets(
    output_dir: Path,
    min_octave: int,
    max_octave: int,
    max_cents_error: float,
) -> int:
    failures = 0
    specs = _build_note_specs(min_octave=min_octave, max_octave=max_octave)
    for note_label, (filename, target_hz) in specs.items():
        path = output_dir / filename
        if not path.exists():
            print(f"missing {note_label:<5} {path}")
            failures += 1
            continue

        samples, sample_rate = _read_wav_as_floats(path)
        estimated_hz = _estimate_frequency_autocorrelation(
            samples=samples,
            sample_rate=sample_rate,
            min_frequency_hz=target_hz * 0.80,
            max_frequency_hz=target_hz * 1.20,
        )
        cents_error = 1200.0 * math.log2(estimated_hz / target_hz)
        within = abs(cents_error) <= max_cents_error
        status = "ok" if within else "fail"
        if not within:
            failures += 1
        print(
            f"{status:<4} {note_label:<5} target={target_hz:9.4f}Hz "
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
        "--min-octave",
        type=int,
        default=DEFAULT_MIN_OCTAVE,
        help="Lowest octave to generate/verify (inclusive).",
    )
    parser.add_argument(
        "--max-octave",
        type=int,
        default=DEFAULT_MAX_OCTAVE,
        help="Highest octave to generate/verify (inclusive).",
    )
    parser.add_argument(
        "--max-cents",
        type=float,
        default=5.0,
        help="Maximum allowed absolute tuning error in cents for verification.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.min_octave > args.max_octave:
        print("--min-octave must be <= --max-octave.")
        return 2

    output_dir = Path(args.output_dir)
    run_generate = args.generate or (not args.generate and not args.verify)
    run_verify = args.verify or (not args.generate and not args.verify)

    if run_generate:
        generate_assets(
            output_dir=output_dir,
            min_octave=args.min_octave,
            max_octave=args.max_octave,
        )
    if run_verify:
        return verify_assets(
            output_dir=output_dir,
            min_octave=args.min_octave,
            max_octave=args.max_octave,
            max_cents_error=args.max_cents,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
