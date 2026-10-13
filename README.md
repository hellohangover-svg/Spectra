# Spectra

Original real-time audio analyzer for iOS 26 (SwiftUI + Liquid Glass, AVAudioEngine, Accelerate).

## Setup
1. `brew install xcodegen`
2. `cd Spectra && xcodegen generate && open Spectra.xcodeproj`
3. Set your signing team, run on a device (the simulator mic is not meaningful), then run the tests (Cmd+U).

## Included
- Calibrated FFT spectrum (Hann / Blackman / flat-top / rectangular), exponential averaging, peak hold
- Separate amplitude (coherent gain) and broadband (noise power gain) scaling
- A/C/Z weighting, Fast/Slow time weighting on the broadband level
- 94 dB / 1 kHz calibrator workflow, persisted offset
- Sine / white / pink generator with a -6 dBFS safety cap
- `.measurement` audio session mode (no AGC / voice processing)
- Unit tests for level accuracy, flat-top scalloping, Parseval broadband level, weighting curves

## Roadmap (superseded, see Features below)
- Time-domain A/C filters + Leq / Lmax / Lmin / percentiles (IEC 61672 behavior)
- 1/1 and 1/3 octave filter banks (IEC 61260)
- Metal renderer, spectrogram, scope view with triggering
- Microphone calibration-file import, multichannel USB input
- CSV / image export, recording + replay
- Replace generator parameter races with atomics

## Octave analyzer (IEC 61260-style)
- Base-10 band layout: 1/1 (31.5 Hz to 16 kHz) and 1/3 (20 Hz to 20 kHz); bands that would reach Nyquist are dropped.
- 6th-order Butterworth band-pass per band, designed by band-pass transform + bilinear transform with prewarped edges, unity gain at center, -3 dB at the nominal band edges.
- Double-precision biquads, per-sample mean-square detector with Fast (125 ms) / Slow (1 s) exponential time weighting.
- Leq since reset and Lmax (ignored for the first second after a reset to skip filter start-up).
- Overall level = weighted sum of band powers (A/C/Z applied at band centers).
- Note: the built-in tests check center gain, -3 dB edges, and rejection; a full IEC 61260 class 1/2 verification (attenuation masks over the whole range) still needs a dedicated test rig.
- Possible optimization: multirate decimation for the low bands (not needed for correctness).

## Features
- **Meter:** time-domain A/C/Z weighting, Fast/Slow, Lp, Leq, Lmax, Lmin, Lpeak, L10/L50/L90, 60 s history
- **Spectrum:** calibrated FFT, windows, averaging, peak hold, interpolated dominant-peak readout
- **Octave:** 1/1 and 1/3 octave filter bank with Leq/Lmax
- **Scope:** triggered waveform, gain, freeze
- **Spectrogram:** scrolling log-frequency waterfall
- **Generator:** sine / white / pink noise (lock-protected parameters, -6 dBFS cap)
- **Calibrate:** 94 dB / 1 kHz workflow (uses the meter)
- **Export:** CSV (meter, octave, spectrum) and spectrum PNG through the share sheet
- Robustness: audio interruption and route/sample-rate change handling, screen stays awake while measuring
- Weighting filters are accurate to <0.2 dB through 2 kHz and within about 1 dB through 12.5 kHz at 48 kHz
  (bilinear warping); this is not a certified IEC 61672 instrument. Certification needs a calibrated
  hardware chain and a test lab.
