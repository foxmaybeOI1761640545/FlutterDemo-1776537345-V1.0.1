#!/usr/bin/env python3
"""Regenerate ear-training note assets with timbre matched to ear-mypiano-aaa.

This tool analyzes `assets/audio/ear-mypiano-aaa.WAV` (expected phrase:
12345678 1 1 in C major) and synthesizes a full C3-B7 note set whose harmonic
profile is inferred from that source recording.

Outputs:
  - assets/audio/ear-piano-<degree><octave>.wav (C3-B7)
  - assets/audio/ear-note-<degree>.wav (legacy aliases to octave 5 assets)
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy.io import wavfile

SAMPLE_RATE = 44_100
DURATION_SECONDS = 1.18
ATTACK_SECONDS = 0.006
RELEASE_SECONDS = 0.18
HAMMER_SECONDS = 0.022
TARGET_AMPLITUDE = 0.92

DEFAULT_MIN_OCTAVE = 3
DEFAULT_MAX_OCTAVE = 7
DEFAULT_SOURCE = Path("assets/audio/ear-mypiano-aaa.WAV")
DEFAULT_OUTPUT_DIR = Path("assets/audio")

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


@dataclass(frozen=True)
class Segment:
    start: int
    end: int


def _midi_to_frequency(midi_note: int) -> float:
    return 440.0 * (2.0 ** ((midi_note - 69) / 12.0))


def _read_wav_mono(path: Path) -> tuple[np.ndarray, int]:
    sample_rate, raw = wavfile.read(str(path))
    if raw.ndim == 2:
        mono = raw.astype(np.float64).mean(axis=1)
    else:
        mono = raw.astype(np.float64)

    if raw.dtype == np.int16:
        mono /= 32768.0
    else:
        peak = np.max(np.abs(mono)) if mono.size > 0 else 1.0
        if peak > 0.0:
            mono /= peak
    return mono, sample_rate


def _resample_to_44k1(samples: np.ndarray, source_rate: int) -> np.ndarray:
    if source_rate == SAMPLE_RATE:
        return samples
    target_len = int(round(len(samples) * SAMPLE_RATE / source_rate))
    if target_len <= 1:
        raise ValueError("source clip is too short after resampling")
    src_x = np.linspace(0.0, 1.0, num=len(samples), endpoint=False)
    dst_x = np.linspace(0.0, 1.0, num=target_len, endpoint=False)
    return np.interp(dst_x, src_x, samples)


def _estimate_f0_autocorr(
    samples: np.ndarray,
    sample_rate: int,
    min_hz: float = 90.0,
    max_hz: float = 900.0,
) -> float | None:
    if samples.size < 1024:
        return None

    centered = samples - np.mean(samples)
    windowed = centered * np.hanning(centered.size)
    min_lag = max(2, int(sample_rate / max_hz))
    max_lag = min(windowed.size - 2, int(sample_rate / min_hz))
    if max_lag <= min_lag:
        return None

    corr = np.correlate(windowed, windowed, mode="full")[windowed.size - 1 :]
    corr[:min_lag] = 0.0
    corr[max_lag + 1 :] = 0.0
    lag = int(np.argmax(corr))
    if lag <= 1:
        return None

    if 1 <= lag < corr.size - 1:
        left, mid, right = corr[lag - 1], corr[lag], corr[lag + 1]
        denom = left - (2.0 * mid) + right
        delta = (0.5 * (left - right) / denom) if denom != 0.0 else 0.0
        delta = float(np.clip(delta, -1.0, 1.0))
        refined_lag = lag + delta
    else:
        refined_lag = float(lag)

    if refined_lag <= 0.0:
        return None
    return sample_rate / refined_lag


def _detect_note_segments(samples: np.ndarray) -> list[Segment]:
    frame = 2048
    hop = 256
    if samples.size <= frame:
        return []

    rms_values = []
    for idx in range(0, samples.size - frame, hop):
        window = samples[idx : idx + frame]
        rms_values.append(float(np.sqrt(np.mean(window * window))))
    rms = np.array(rms_values, dtype=np.float64)
    if rms.size == 0:
        return []

    smooth_len = 7
    rms_smooth = np.convolve(
        rms,
        np.ones(smooth_len, dtype=np.float64) / smooth_len,
        mode="same",
    )
    peak = float(np.max(rms_smooth))
    if peak <= 0.0:
        return []
    rms_smooth /= peak

    derivative = np.diff(rms_smooth, prepend=rms_smooth[0])
    threshold = 0.16
    rising = np.where((rms_smooth > threshold) & (derivative > 0.012))[0]

    min_gap_frames = int(0.28 * SAMPLE_RATE / hop)
    seeds: list[int] = []
    last = -10**9
    for candidate in rising:
        if candidate - last >= min_gap_frames:
            seeds.append(int(candidate))
            last = int(candidate)

    if not seeds:
        first = int(np.argmax(rms_smooth > threshold))
        if first > 0:
            seeds = [first]

    refined: list[int] = []
    local_half_win = int(0.08 * SAMPLE_RATE / hop)
    for seed in seeds:
        lo = max(0, seed - local_half_win)
        hi = min(rms_smooth.size, seed + local_half_win + 1)
        local_idx = lo + int(np.argmax(rms_smooth[lo:hi]))
        if not refined or local_idx - refined[-1] >= min_gap_frames:
            refined.append(local_idx)

    starts = [idx * hop for idx in refined]
    segments: list[Segment] = []
    for i, start in enumerate(starts):
        next_start = starts[i + 1] if i + 1 < len(starts) else samples.size
        end = min(next_start, start + int(0.95 * SAMPLE_RATE))
        tail = samples[start:end]
        if tail.size > 0:
            amp = np.abs(tail)
            local_peak = float(np.max(amp))
            if local_peak > 0.0:
                active = np.where(amp > 0.08 * local_peak)[0]
                if active.size > 0:
                    end = start + int(min(tail.size, active[-1] + int(0.06 * SAMPLE_RATE)))
        if end - start > 2048:
            segments.append(Segment(start=start, end=end))
    return segments


def _complex_amplitude(window: np.ndarray, frequency_hz: float) -> complex:
    n = window.size
    t = np.arange(n, dtype=np.float64) / SAMPLE_RATE
    centered = window - np.mean(window)
    taper = np.hanning(n)
    weighted = centered * taper
    phasor = np.exp(-2j * math.pi * frequency_hz * t)
    norm = np.sum(taper)
    if norm <= 0.0:
        return 0.0j
    return np.sum(weighted * phasor) / norm


def _estimate_profile_and_phases(
    samples: np.ndarray,
    segments: list[Segment],
) -> tuple[dict[int, float], dict[int, float], dict[int, float]]:
    if len(segments) < 8:
        raise ValueError(
            "unable to detect enough note events in source file; expected at least 8."
        )

    harmonic_relatives: dict[int, list[float]] = {}
    harmonic_phases: dict[int, list[float]] = {}
    max_harmonic = 10

    for segment in segments[:8]:
        stable_start = segment.start + int(0.06 * SAMPLE_RATE)
        stable_end = min(segment.end - int(0.03 * SAMPLE_RATE), stable_start + int(0.16 * SAMPLE_RATE))
        if stable_end - stable_start < 1024:
            continue

        window = samples[stable_start:stable_end]
        f0 = _estimate_f0_autocorr(window, SAMPLE_RATE, min_hz=110.0, max_hz=420.0)
        if f0 is None:
            continue

        amplitudes: dict[int, float] = {}
        phases: dict[int, float] = {}
        for harmonic in range(1, max_harmonic + 1):
            partial_hz = f0 * harmonic
            if partial_hz >= SAMPLE_RATE * 0.48:
                break
            coeff = _complex_amplitude(window, partial_hz)
            amplitudes[harmonic] = float(abs(coeff))
            phases[harmonic] = float(np.angle(coeff))

        fundamental = amplitudes.get(1, 0.0)
        if fundamental <= 1e-9:
            continue

        for harmonic, amplitude in amplitudes.items():
            harmonic_relatives.setdefault(harmonic, []).append(amplitude / fundamental)
            harmonic_phases.setdefault(harmonic, []).append(phases[harmonic])

    if 1 not in harmonic_relatives:
        raise ValueError("failed to infer harmonic profile from source file")

    profile = {
        harmonic: float(np.median(values))
        for harmonic, values in harmonic_relatives.items()
        if values
    }
    fundamental = profile.get(1, 1.0)
    profile = {harmonic: value / fundamental for harmonic, value in profile.items()}

    # For phase we only need a stable default; median works well enough here.
    phase_profile = {
        harmonic: float(np.median(values))
        for harmonic, values in harmonic_phases.items()
        if values
    }

    # Estimate per-harmonic decay from the first long sustain C3 (segment #9 if present).
    sustain_segment = segments[8] if len(segments) >= 9 else segments[0]
    sustain = samples[sustain_segment.start : sustain_segment.end]
    if sustain.size < int(0.6 * SAMPLE_RATE):
        sustain = samples[segments[0].start : segments[0].end]

    f0_sustain = _estimate_f0_autocorr(sustain[: int(0.28 * SAMPLE_RATE)], SAMPLE_RATE)
    if f0_sustain is None:
        f0_sustain = 130.8128  # C3 fallback

    early_a = int(0.09 * SAMPLE_RATE)
    early_b = int(0.25 * SAMPLE_RATE)
    late_a = int(0.42 * SAMPLE_RATE)
    late_b = int(0.72 * SAMPLE_RATE)
    if sustain.size < late_b + 4:
        # fallback to a shorter late window if the segment is too short
        late_a = max(early_b + 1, int(sustain.size * 0.45))
        late_b = max(late_a + 512, int(sustain.size * 0.82))

    early_window = sustain[early_a:early_b]
    late_window = sustain[late_a:late_b]
    dt = max(0.08, (late_a - early_a) / SAMPLE_RATE)
    eps = 1e-8

    decay_rates: dict[int, float] = {}
    for harmonic in sorted(profile):
        partial_hz = harmonic * f0_sustain
        early_amp = abs(_complex_amplitude(early_window, partial_hz))
        late_amp = abs(_complex_amplitude(late_window, partial_hz))
        if early_amp <= eps or late_amp <= eps:
            decay = 2.0 + harmonic * 0.9
        else:
            decay = math.log((early_amp + eps) / (late_amp + eps)) / dt
        decay_rates[harmonic] = float(np.clip(decay, 0.8, 12.0))

    return profile, phase_profile, decay_rates


def _synthesize_note(
    frequency_hz: float,
    harmonic_profile: dict[int, float],
    phase_profile: dict[int, float],
    decay_rates: dict[int, float],
) -> np.ndarray:
    total_samples = int(round(SAMPLE_RATE * DURATION_SECONDS))
    attack_samples = max(1, int(round(SAMPLE_RATE * ATTACK_SECONDS)))
    release_samples = max(1, int(round(SAMPLE_RATE * RELEASE_SECONDS)))
    hammer_samples = max(1, int(round(SAMPLE_RATE * HAMMER_SECONDS)))
    t = np.arange(total_samples, dtype=np.float64) / SAMPLE_RATE

    output = np.zeros(total_samples, dtype=np.float64)
    for harmonic, rel_amp in sorted(harmonic_profile.items()):
        partial_hz = harmonic * frequency_hz
        if partial_hz >= SAMPLE_RATE * 0.48:
            continue
        phase = phase_profile.get(harmonic, 0.0)
        decay = decay_rates.get(harmonic, 2.0 + harmonic * 0.9)
        output += rel_amp * np.exp(-decay * t) * np.sin(
            (2.0 * math.pi * partial_hz * t) + phase
        )

    # Add a soft hammer-like transient for piano articulation.
    hammer_t = t[:hammer_samples]
    hammer_env = 1.0 - (np.arange(hammer_samples, dtype=np.float64) / hammer_samples)
    output[:hammer_samples] += (
        0.075
        * hammer_env
        * np.sin((2.0 * math.pi * frequency_hz * 6.2 * hammer_t) + 0.8)
    )

    attack_env = np.ones(total_samples, dtype=np.float64)
    attack_env[:attack_samples] = np.linspace(0.0, 1.0, attack_samples, endpoint=False)

    release_env = np.ones(total_samples, dtype=np.float64)
    release_env[-release_samples:] = np.linspace(1.0, 0.0, release_samples, endpoint=True)

    overall_env = np.exp(-1.75 * t)
    output *= attack_env * release_env * overall_env

    peak = float(np.max(np.abs(output)))
    if peak > 1e-12:
        output *= TARGET_AMPLITUDE / peak
    return output


def _float_to_pcm16(samples: np.ndarray) -> np.ndarray:
    clipped = np.clip(samples, -1.0, 1.0)
    return np.round(clipped * 32767.0).astype(np.int16)


def _write_note_asset(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    wavfile.write(str(path), SAMPLE_RATE, _float_to_pcm16(samples))


def _build_target_specs(
    min_octave: int,
    max_octave: int,
) -> dict[str, tuple[str, float]]:
    specs: dict[str, tuple[str, float]] = {}
    for octave in range(min_octave, max_octave + 1):
        c_midi = (octave + 1) * 12
        for degree_name, slug, semitone in DEGREE_SPECS:
            midi_note = c_midi + semitone
            frequency_hz = _midi_to_frequency(midi_note)
            filename = f"ear-piano-{slug}{octave}.wav"
            specs[f"{degree_name}{octave}"] = (filename, frequency_hz)
    return specs


def generate_assets(
    source_wav: Path,
    output_dir: Path,
    min_octave: int,
    max_octave: int,
) -> None:
    samples, source_rate = _read_wav_mono(source_wav)
    samples = _resample_to_44k1(samples, source_rate)
    segments = _detect_note_segments(samples)
    if len(segments) < 8:
        raise RuntimeError(
            f"detected only {len(segments)} note segments in {source_wav}; expected >= 8"
        )

    profile, phases, decay_rates = _estimate_profile_and_phases(samples, segments)
    target_specs = _build_target_specs(min_octave=min_octave, max_octave=max_octave)

    print("detected source note segments:", len(segments))
    print("harmonic profile (relative):")
    for harmonic in sorted(profile):
        print(
            f"  h{harmonic:02d}: amp={profile[harmonic]:.4f} decay={decay_rates.get(harmonic, 0.0):.3f}"
        )

    for note_label, (filename, frequency_hz) in target_specs.items():
        path = output_dir / filename
        rendered = _synthesize_note(
            frequency_hz=frequency_hz,
            harmonic_profile=profile,
            phase_profile=phases,
            decay_rates=decay_rates,
        )
        _write_note_asset(path, rendered)
        print(f"generated {note_label:<5} {path} @ {frequency_hz:9.4f}Hz")

    # Keep legacy single-octave aliases for compatibility.
    for degree_name, slug, _ in DEGREE_SPECS:
        source_name = f"ear-piano-{slug}5.wav"
        source_path = output_dir / source_name
        legacy_path = output_dir / f"ear-note-{slug}.wav"
        legacy_path.write_bytes(source_path.read_bytes())
        print(f"aliased  {legacy_path} <= {source_path.name}")


def verify_assets(output_dir: Path, min_octave: int, max_octave: int, max_cents: float) -> int:
    failures = 0
    specs = _build_target_specs(min_octave=min_octave, max_octave=max_octave)
    for note_label, (filename, target_hz) in specs.items():
        path = output_dir / filename
        if not path.exists():
            print(f"missing {note_label:<5} {path}")
            failures += 1
            continue

        samples, sample_rate = _read_wav_mono(path)
        if sample_rate != SAMPLE_RATE:
            samples = _resample_to_44k1(samples, sample_rate)
        probe = samples[int(0.06 * SAMPLE_RATE) : int(0.40 * SAMPLE_RATE)]
        estimate_hz = _estimate_f0_autocorr(
            probe,
            SAMPLE_RATE,
            min_hz=target_hz * 0.80,
            max_hz=target_hz * 1.20,
        )
        if estimate_hz is None:
            print(f"fail {note_label:<5} unable to estimate frequency")
            failures += 1
            continue

        cents = 1200.0 * math.log2(estimate_hz / target_hz)
        ok = abs(cents) <= max_cents
        status = "ok" if ok else "fail"
        if not ok:
            failures += 1
        print(
            f"{status:<4} {note_label:<5} target={target_hz:9.4f}Hz "
            f"measured={estimate_hz:9.4f}Hz error={cents:+7.3f} cents"
        )

    if failures > 0:
        print(f"verification failed: {failures} note(s) exceed +/-{max_cents:.2f} cents")
    else:
        print(f"verification passed: all notes within +/-{max_cents:.2f} cents")
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate ear-training note assets matched to ear-mypiano-aaa timbre.",
    )
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="source WAV path")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="target assets directory",
    )
    parser.add_argument("--min-octave", type=int, default=DEFAULT_MIN_OCTAVE)
    parser.add_argument("--max-octave", type=int, default=DEFAULT_MAX_OCTAVE)
    parser.add_argument("--generate", action="store_true", help="generate assets")
    parser.add_argument("--verify", action="store_true", help="verify generated pitch")
    parser.add_argument(
        "--max-cents",
        type=float,
        default=8.0,
        help="max acceptable pitch error in cents for verification",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.generate and not args.verify:
        print("nothing to do: enable --generate and/or --verify")
        return 1
    if args.min_octave > args.max_octave:
        print("invalid octave range: min-octave must be <= max-octave")
        return 1
    if not args.source.exists():
        print(f"source file not found: {args.source}")
        return 1

    try:
        if args.generate:
            generate_assets(
                source_wav=args.source,
                output_dir=args.output_dir,
                min_octave=args.min_octave,
                max_octave=args.max_octave,
            )
        if args.verify:
            failures = verify_assets(
                output_dir=args.output_dir,
                min_octave=args.min_octave,
                max_octave=args.max_octave,
                max_cents=args.max_cents,
            )
            if failures > 0:
                return 2
        return 0
    except Exception as exc:  # pragma: no cover - CLI guard
        print(f"error: {exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
