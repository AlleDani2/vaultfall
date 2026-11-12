#!/usr/bin/env python3
"""
Sintetizza TUTTO l'audio di VAULTFALL in modo procedurale e deterministico (docs/21, assets_plan/audio_manifest.csv).
Solo numpy + modulo `wave` della libreria standard (+ `ffmpeg` per l'OGG, se presente): nessun campione di terzi,
nessuna licenza, nessun download. I suoni sono quindi generati dal progetto stesso (docs/21_audio.md §5 e docs/24).

Contenuto (secondo giro, AUDIO-2):
  - effetti: UI coerente (pentatonica di Do), 17 mansioni x 3 varianti, stinger (vittoria, sconfitta, level up,
    missione, prestigio, Era), rivelazioni per rarità (stereo con ambiente);
  - musica: 12 contesti x 2-3 varianti (26 tracce STEREO di 29-48 s) in loop senza giunzione (buffer circolare,
    riverbero per convoluzione circolare), livellate sulla stessa loudness stimata (K-weighting semplificato);
  - `--report` decodifica gli OGG e misura picco, RMS, loudness stimata, centroide spettrale, click al punto di loop,
    silenzi e durata; `--check` esce con codice != 0 se un limite è violato (usato da tests/test_audio_levels.py).

Formato: 22,05 kHz; effetti mono (stinger stereo), musica stereo. OGG Vorbis se `ffmpeg` è nel PATH, altrimenti WAV
16 bit (oppure forzato con --wav). Stesso seme -> stessi byte.

Uscita: game/assets/audio/sfx/*.{ogg,wav} e game/assets/audio/music/*.{ogg,wav}
Uso:  python tools/make_audio.py [--wav] [--only NOME] [--out CARTELLA] [--report] [--check]
Il catalogo evento->file sta in game/src/autoload/AudioManager.gd; il test game/tests/test_audio.gd verifica che
ogni file esista e che i contesti musicali abbiano le loro tracce.
"""
import argparse, csv, json, os, shutil, subprocess, sys, tempfile, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 22050


# ------------------------------------------------------------------ utilità di sintesi
def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def rng_for(name):
    seed = sum((i + 1) * ord(c) for i, c in enumerate(name)) & 0xFFFFFFFF
    return np.random.default_rng(seed)


def tvec(dur):
    return np.arange(int(dur * SR)) / SR


def fade(x, a=0.003, r=0.01):
    n = len(x)
    na, nr = min(n, int(a * SR)), min(n, int(r * SR))
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nr:
        x[-nr:] *= np.linspace(1, 0, nr)
    return x


def tone(freq, dur, harm=(1.0,), tau=0.2, attack=0.004, vib=0.0, sweep=0.0):
    """Nota additiva con decadimento esponenziale (pizzicato/campana). sweep: variazione relativa di frequenza."""
    t = tvec(dur)
    f = freq * (1.0 + sweep * np.exp(-t * 18.0)) if sweep else freq
    ph = 2 * np.pi * np.cumsum(np.broadcast_to(f, t.shape)) / SR if sweep else 2 * np.pi * freq * t
    if vib:
        ph = ph + vib * np.sin(2 * np.pi * 5.0 * t)
    y = np.zeros_like(t)
    for k, a in enumerate(harm, 1):
        y += a * np.sin(k * ph)
    env = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-t / tau)
    return fade(y * env / max(1.0, sum(abs(a) for a in harm) * 0.6))


def sustained(freq, dur, harm=(1.0, 0.3, 0.1), attack=0.3, release=0.4, trem=0.0, detune=0.0, ph=0.0):
    """Nota tenuta (pad, flauto, fisarmonica) con attacco/rilascio lenti."""
    t = tvec(dur)
    y = np.zeros_like(t)
    for d in ((0.0,) if not detune else (-detune, detune)):
        for k, a in enumerate(harm, 1):
            y += a * np.sin(2 * np.pi * freq * (1 + d) * k * t + ph * k)
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, (dur - t) / release)
    if trem:
        env = env * (1.0 - trem + trem * np.sin(2 * np.pi * 4.5 * t))
    return y * env / max(1.0, sum(harm) * (2 if detune else 1) * 0.7)


def noise_band(dur, lo, hi, rng, tau=0.05, attack=0.001):
    """Rumore filtrato in banda (FFT) con inviluppo esponenziale."""
    n = int(dur * SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1.0 / SR)
    spec *= ((fr >= lo) & (fr <= hi)).astype(float)
    y = np.fft.irfft(spec, n)
    y /= max(1e-9, np.max(np.abs(y)))
    t = np.arange(n) / SR
    return fade(y * np.minimum(1.0, t / attack) * np.exp(-t / tau))


def put(buf, sig, at, gain=1.0):
    i = int(at * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i] * gain


def silence(dur):
    return np.zeros(int(dur * SR))


def norm(x, peak):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


# ------------------------------------------------------------------ primitive aggiuntive
def inharm(freq, dur, tau=0.2, ratios=(1.0, 2.32, 4.25, 6.63), amps=(1.0, 0.6, 0.35, 0.2), attack=0.001):
    """Parziali non armonici (metallo, campane): ogni parziale decade più in fretta del precedente."""
    t = tvec(dur)
    y = np.zeros_like(t)
    for k, (rt, a) in enumerate(zip(ratios, amps)):
        f = freq * rt
        if f < SR * 0.45:
            y += a * np.sin(2 * np.pi * f * t) * np.exp(-t / (tau / (1.0 + 0.5 * k)))
    return fade(y * np.minimum(1.0, t / attack) / max(1.0, sum(amps) * 0.6), 0.002, 0.01)


def noise_sweep(dur, f0, f1, rng, width=0.6, tau=None, attack=0.004, steps=9, release=0.02):
    """Rumore a banda mobile da f0 a f1 (spazzata, 'whoosh', raspa)."""
    n = int(dur * SR)
    spec = np.fft.rfft(rng.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1.0 / SR)
    out = np.zeros(n)
    pos = np.arange(n) / max(1, n - 1) * (steps - 1)
    for i in range(steps):
        c = f0 * (f1 / f0) ** (i / (steps - 1))
        m = ((fr >= c * (1 - width / 2)) & (fr <= c * (1 + width / 2))).astype(float)
        seg = np.fft.irfft(spec * m, n)
        seg /= max(1e-9, np.max(np.abs(seg)))
        out += seg * np.clip(1.0 - np.abs(pos - i), 0.0, 1.0)
    t = np.arange(n) / SR
    env = np.minimum(1.0, t / attack)
    if tau:
        env = env * np.exp(-t / tau)
    return fade(out * env, 0.002, release)


def crackle(dur, rate, rng, lo, hi, tau=None):
    """Impulsi casuali filtrati (sfrigolio, foglie, ghiaia)."""
    n = int(dur * SR)
    imp = (rng.random(n) < rate / SR) * rng.standard_normal(n)
    spec = np.fft.rfft(imp)
    fr = np.fft.rfftfreq(n, 1.0 / SR)
    y = np.fft.irfft(spec * ((fr >= lo) & (fr <= hi)), n)
    y /= max(1e-9, np.max(np.abs(y)))
    t = np.arange(n) / SR
    return fade(y * (np.exp(-t / tau) if tau else 1.0), 0.003, 0.02)


def blip(f0, f1, dur, tau=None):
    """Bolla/goccia: sinusoide che sale (o scende) di tono."""
    t = tvec(dur)
    f = f0 * (f1 / f0) ** (t / max(dur, 1e-6))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return fade(np.sin(ph) * np.exp(-t / (tau or dur * 0.5)), 0.002, 0.01)


def room(x, rng, rt=0.45, wet=0.28, lp=4500.0):
    """Ambiente breve: stereo da mono con coda (convoluzione con rumore che decade). Ritorna (n, 2)."""
    tail = int(rt * 1.6 * SR)
    n = len(x) + tail
    out = np.zeros((n, 2))
    xs = np.zeros(n)
    xs[: len(x)] = x
    X = np.fft.rfft(xs)
    fr = np.fft.rfftfreq(n, 1.0 / SR)
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR / (rt / 6.9))
        ir[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
        IR = np.fft.rfft(ir) / (1.0 + (fr / lp) ** 2)
        IR /= max(1e-9, np.sqrt(np.mean(np.abs(IR) ** 2)))
        out[:, ch] = xs * (1.0 - wet) + np.fft.irfft(X * IR, n) * wet * 0.5
    return fade_st(out)


def fade_st(x, a=0.002, r=0.03):
    n = len(x)
    na, nr = min(n, int(a * SR)), min(n, int(r * SR))
    x[:na] *= np.linspace(0, 1, na)[:, None]
    x[-nr:] *= np.linspace(1, 0, nr)[:, None]
    return x


# ------------------------------------------------------------------ effetti: interfaccia (pentatonica di Do)
BELL = (1.0, 0.0, 0.35, 0.0, 0.12)
SOFT = (1.0, 0.25, 0.08)
WOOD = (1.0, 0.5, 0.2)


def _chord(b, notes, at, dur=0.9, tau=0.3, gain=1.0, harm=SOFT):
    for k, m in enumerate(notes):
        put(b, tone(mtof(m), dur, harm, tau=tau), at + 0.012 * k, gain)


def _shimmer(b, notes, at, step=0.07, gain=0.4, tau=0.15):
    for i, m in enumerate(notes):
        put(b, tone(mtof(m), 0.6, BELL, tau=tau), at + step * i, gain)


def sfx_ui_click(r):
    b = silence(0.07)
    put(b, tone(1400, 0.06, (1.0, 0.2), tau=0.012), 0.0)
    put(b, noise_band(0.02, 2000, 6000, r, 0.004), 0.0, 0.4)
    return norm(b, 0.45)


def sfx_ui_confirm(r):
    b = silence(0.4)
    put(b, tone(mtof(76), 0.3, SOFT, tau=0.09), 0.0)
    put(b, tone(mtof(83), 0.3, SOFT, tau=0.12), 0.07)
    return norm(b, 0.5)


def sfx_ui_error(r):
    b = silence(0.42)
    put(b, tone(mtof(55), 0.22, (1.0, 0.6, 0.3), tau=0.07), 0.0)
    put(b, tone(mtof(51), 0.28, (1.0, 0.6, 0.3), tau=0.10), 0.12)
    return norm(b, 0.5)


def sfx_ui_notify(r):
    b = tone(mtof(84), 0.5, BELL, tau=0.16)
    put(b, tone(mtof(91), 0.5, BELL, tau=0.12), 0.0, 0.5)
    return norm(b, 0.45)


def sfx_action_done(r):
    b = silence(0.55)
    put(b, tone(mtof(84), 0.5, BELL, tau=0.14), 0.0)
    put(b, tone(mtof(91), 0.45, BELL, tau=0.12), 0.09, 0.7)
    return norm(b, 0.4)


def sfx_ui_achievement(r):
    b = silence(1.3)
    for i, m in enumerate((72, 76, 79, 84)):
        put(b, tone(mtof(m), 0.8, BELL, tau=0.3), 0.11 * i, 0.8)
    put(b, tone(mtof(88), 0.9, (1.0, 0.0, 0.2), tau=0.4), 0.44, 0.7)
    _chord(b, (60, 64, 67), 0.0, 1.0, 0.35, 0.5)
    return room(norm(b, 0.5), r, 0.6, 0.3)


def sfx_ui_pet(r):
    b = silence(0.9)
    for i, m in enumerate((79, 84, 88, 86, 91)):
        put(b, tone(mtof(m), 0.35, BELL, tau=0.1), 0.08 * i, 0.8)
    put(b, tone(mtof(72), 0.6, SOFT, tau=0.25), 0.0, 0.5)
    return room(norm(b, 0.45), r, 0.4, 0.22)


def sfx_ui_star(r):
    b = silence(1.2)
    for i, m in enumerate((84, 88, 91, 96)):
        put(b, tone(mtof(m), 0.7, BELL, tau=0.22), 0.07 * i, 0.9 - 0.1 * i)
    put(b, tone(mtof(72), 0.9, SOFT, tau=0.4), 0.0, 0.6)
    return room(norm(b, 0.45), r, 0.55, 0.3)


def sfx_ui_welcome(r):
    """Jingle del 'Bentornato': quattro note calde ascendenti, breve e non invadente."""
    b = silence(1.4)
    for i, m in enumerate((64, 67, 72, 76)):
        put(b, tone(mtof(m), 0.8, (1.0, 0.3, 0.1), tau=0.3), 0.16 * i, 0.9)
    put(b, tone(mtof(84), 0.8, BELL, tau=0.3), 0.55, 0.5)
    return room(norm(b, 0.42), r, 0.6, 0.3)


def sfx_ui_unlock(r):
    b = silence(0.8)
    put(b, noise_sweep(0.3, 500, 3500, r, 0.7, None, 0.02, 8, 0.04), 0.0, 0.18)
    put(b, tone(mtof(79), 0.5, BELL, tau=0.18), 0.22)
    put(b, tone(mtof(86), 0.55, BELL, tau=0.22), 0.30, 0.8)
    return norm(b, 0.42)


def sfx_crate_open(r):
    b = silence(1.2)
    sw = noise_band(0.45, 300, 1800, r, 10.0)
    sw *= np.linspace(0, 1, len(sw)) ** 2
    put(b, fade(sw, 0.05, 0.05), 0.0, 0.35)
    for m in (64, 68, 71):
        put(b, tone(mtof(m), 0.8, SOFT, tau=0.3), 0.45)
    put(b, tone(mtof(83), 0.6, BELL, tau=0.25), 0.5, 0.5)
    return norm(b, 0.5)


def sfx_reel_tick(r):
    b = silence(0.05)
    put(b, tone(1000, 0.045, (1.0, 0.4), tau=0.009), 0.0)
    put(b, noise_band(0.015, 1500, 5000, r, 0.003), 0.0, 0.3)
    return norm(b, 0.4)


def sfx_hit(r):
    b = silence(0.22)
    put(b, tone(150, 0.2, (1.0, 0.4), tau=0.05, sweep=1.0), 0.0)
    put(b, noise_band(0.12, 200, 2500, r, 0.025), 0.0, 0.7)
    return norm(b, 0.5)


def sfx_coin(r):
    b = silence(0.4)
    put(b, tone(mtof(96), 0.35, BELL, tau=0.07), 0.0)
    put(b, tone(mtof(103), 0.3, BELL, tau=0.09), 0.055, 0.8)
    return norm(b, 0.38)


def sfx_sell(r):
    b = silence(0.55)
    put(b, tone(mtof(91), 0.3, BELL, tau=0.07), 0.0, 0.8)
    put(b, tone(mtof(96), 0.3, BELL, tau=0.07), 0.07)
    put(b, tone(mtof(100), 0.35, BELL, tau=0.1), 0.15, 0.8)
    return norm(b, 0.4)


# ------------------------------------------------------------------ effetti: stinger (stereo con ambiente)
def sfx_level_up(r):
    b = silence(1.7)
    for i, m in enumerate((72, 76, 79, 84)):
        put(b, tone(mtof(m), 0.8, (1.0, 0.3, 0.12), tau=0.25), 0.1 * i)
    _chord(b, (60, 67), 0.0, 1.2, 0.4, 0.5)
    put(b, tone(mtof(88), 1.0, BELL, tau=0.35), 0.4, 0.5)
    _shimmer(b, (91, 95, 100), 0.62, 0.08, 0.28)
    return room(norm(b, 0.55), r, 0.55, 0.28)


def sfx_quest_done(r):
    b = silence(1.6)
    put(b, tone(110, 0.2, (1.0, 0.5), tau=0.05, sweep=0.8), 0.0, 0.8)           # sigillo
    put(b, noise_band(0.08, 300, 2500, r, 0.02), 0.0, 0.4)
    for i, m in enumerate((72, 79, 84)):
        put(b, tone(mtof(m), 0.8, (1.0, 0.3, 0.1), tau=0.3), 0.18 + 0.12 * i)
    _chord(b, (64, 71, 76), 0.5, 1.0, 0.4, 0.55)
    _shimmer(b, (88, 91), 0.72, 0.1, 0.3)
    return room(norm(b, 0.5), r, 0.55, 0.28)


def sfx_victory(r):
    b = silence(2.2)
    for m, at, d in ((67, 0.0, 0.2), (72, 0.18, 0.2), (76, 0.36, 0.2), (79, 0.54, 1.0)):
        _chord(b, (m, m - 12), at, d + 0.3, 0.45 if at > 0.5 else 0.16, 0.8)
    _chord(b, (72, 76, 79, 84), 0.54, 1.4, 0.55, 0.55)
    _shimmer(b, (91, 96, 100, 103), 0.9, 0.09, 0.3)
    return room(norm(b, 0.55), r, 0.75, 0.3)


def sfx_defeat(r):
    """Sconfitta: discesa lenta e morbida in modo minore, senza durezza."""
    b = silence(2.4)
    for i, m in enumerate((69, 65, 62, 57)):
        _chord(b, (m, m - 12), 0.42 * i, 1.3, 0.55, 0.7, (1.0, 0.5, 0.25, 0.1))
    put(b, tone(mtof(45), 1.6, SOFT, tau=0.9), 1.2, 0.6)
    return room(norm(b, 0.5), r, 0.9, 0.32, 2800.0)


def sfx_death(r):
    b = silence(1.8)
    for i, m in enumerate((57, 54, 50)):
        put(b, tone(mtof(m), 1.0, (1.0, 0.5, 0.25, 0.1), tau=0.45), 0.35 * i)
        put(b, tone(mtof(m - 12), 1.0, SOFT, tau=0.45), 0.35 * i, 0.6)
    return room(norm(b, 0.5), r, 0.6, 0.25, 3000.0)


def sfx_prestige(r):
    """Prestigio / rito: salita ampia con respiro, accordo pieno e scintillio lungo."""
    b = silence(3.2)
    put(b, noise_sweep(1.0, 200, 2600, r, 0.8, None, 0.5, 10, 0.2), 0.0, 0.16)
    for i, m in enumerate((48, 55, 60, 64, 67, 72)):
        _chord(b, (m,), 0.2 * i, 2.2, 0.8, 0.55)
    _chord(b, (60, 64, 67, 72, 76), 1.25, 1.8, 0.9, 0.6)
    _shimmer(b, (91, 95, 96, 100, 103, 108), 1.5, 0.11, 0.3, 0.3)
    return room(norm(b, 0.6), r, 1.1, 0.34)


def sfx_era(r):
    """Nuova Era: due accordi sovrapposti (quinte aperte) e campana profonda."""
    b = silence(3.6)
    put(b, inharm(mtof(36), 3.2, 1.4, (1.0, 2.0, 2.76, 5.4), (1.0, 0.5, 0.4, 0.2)), 0.0, 0.8)
    _chord(b, (43, 50, 55, 59), 0.15, 2.4, 0.9, 0.5)
    _chord(b, (50, 57, 62, 66), 1.35, 2.2, 0.9, 0.55)
    _shimmer(b, (86, 90, 93, 98, 102), 1.6, 0.14, 0.28, 0.35)
    return room(norm(b, 0.6), r, 1.2, 0.36)


def _reveal(low, up, spark, dur, tau, up_at=0.2, ring=None):
    b = silence(dur)
    _chord(b, low, 0.0, dur * 0.8, tau, 0.9)
    if up:
        _chord(b, up, up_at, dur * 0.75, tau * 1.1, 0.7)
    if spark:
        _shimmer(b, spark, up_at + 0.2, 0.08, 0.28)
    if ring:
        put(b, inharm(mtof(ring), dur * 0.8, tau * 2.0, (1.0, 2.76, 5.4), (1.0, 0.4, 0.2)), 0.0, 0.35)
    return b


def sfx_reveal_rare(r):
    return room(norm(_reveal((72, 79), (), (), 0.8, 0.2), 0.4), r, 0.4, 0.2)


def sfx_reveal_epic(r):
    return room(norm(_reveal((69, 72, 76), (), (88,), 1.1, 0.28), 0.45), r, 0.55, 0.24)


def sfx_reveal_legendary(r):
    return room(norm(_reveal((67, 71, 74), (79,), (91, 95), 1.4, 0.34, 0.18, 55), 0.5), r, 0.7, 0.28)


def sfx_reveal_mythic(r):
    return room(norm(_reveal((64, 68, 71), (76, 80, 83), (88, 92, 95), 1.8, 0.4, 0.2, 52), 0.55), r, 0.85, 0.3)


def sfx_reveal_relic(r):
    """Fanfara breve per ★: quinte ascendenti e scintillio. Mai monete/sirene (docs/21 §1)."""
    b = silence(2.8)
    put(b, inharm(mtof(48), 2.4, 1.2, (1.0, 2.0, 2.76, 5.4), (1.0, 0.4, 0.3, 0.15)), 0.0, 0.6)
    for i, m in enumerate((60, 67, 72, 76)):
        _chord(b, (m, m + 12), 0.14 * i, 1.4, 0.5, 0.8)
    _chord(b, (79, 83, 88), 0.62, 1.6, 0.6, 0.85)
    _shimmer(b, (91, 95, 100, 103, 107, 112), 0.85, 0.075, 0.38, 0.2)
    return room(norm(b, 0.6), r, 1.0, 0.32)


# ------------------------------------------------------------------ effetti: combattimento e commercio (AUDIO-3)
def sfx_hit_crit(r):
    """Colpo critico: colpo secco + schiocco metallico brillante (si distingue dal colpo normale)."""
    b = silence(0.45)
    put(b, tone(170, 0.2, (1.0, 0.45), tau=0.05, sweep=1.2), 0.0)
    put(b, noise_band(0.12, 250, 3200, r, 0.02), 0.0, 0.75)
    put(b, inharm(1500, 0.38, 0.12, (1.0, 2.76, 5.4), (1.0, 0.45, 0.2)), 0.02, 0.5)
    put(b, tone(mtof(88), 0.3, BELL, tau=0.09), 0.05, 0.3)
    return norm(b, 0.55)


def sfx_dodge(r):
    """Schivata: soffio d'aria che passa (rumore a banda mobile verso l'alto), niente impatto."""
    b = silence(0.3)
    put(b, noise_sweep(0.24, 600, 3000, r, 0.8, 0.09, 0.03, 8, 0.06), 0.0, 0.8)
    return norm(b, 0.4)


def sfx_hurt(r):
    """Colpo subito dall'eroe: tonfo sordo e breve, grave (non deve stancare: avviene spesso)."""
    b = silence(0.28)
    put(b, tone(95, 0.24, (1.0, 0.5, 0.2), tau=0.06, sweep=0.9), 0.0)
    put(b, noise_band(0.1, 120, 900, r, 0.03), 0.0, 0.6)
    return norm(b, 0.5)


def sfx_kill(r):
    """Mostro sconfitto: colpo pieno e piccolo 'crollo' discendente."""
    b = silence(0.55)
    put(b, tone(140, 0.25, (1.0, 0.45), tau=0.06, sweep=1.0), 0.0)
    put(b, noise_band(0.15, 150, 2200, r, 0.04), 0.0, 0.7)
    put(b, blip(520, 170, 0.34, 0.12), 0.05, 0.35)
    return norm(b, 0.5)


def sfx_buy(r):
    """Acquisto: due monete che cadono e un tintinnio grave (diverso da vendita, che sale)."""
    b = silence(0.6)
    put(b, tone(mtof(100), 0.3, BELL, tau=0.07), 0.0, 0.8)
    put(b, tone(mtof(96), 0.3, BELL, tau=0.07), 0.07)
    put(b, tone(mtof(91), 0.35, BELL, tau=0.1), 0.15, 0.8)
    put(b, noise_band(0.05, 1500, 4500, r, 0.01), 0.0, 0.15)
    return norm(b, 0.4)


def sfx_crate_found(r):
    """Cassa trovata: scatto di legno e due note ascendenti (invito, non fanfara)."""
    b = silence(0.9)
    put(b, tone(210, 0.12, WOOD, tau=0.03, sweep=0.6), 0.0, 0.8)
    put(b, noise_band(0.06, 300, 2000, r, 0.015), 0.0, 0.4)
    put(b, tone(mtof(72), 0.5, SOFT, tau=0.2), 0.16, 0.7)
    put(b, tone(mtof(79), 0.6, BELL, tau=0.25), 0.28, 0.6)
    return norm(b, 0.45)


def sfx_drop_rare(r):
    """Oggetto raro caduto: scintillio breve ascendente (non chiude il ducking: e' piu' corto di una rivelazione)."""
    b = silence(1.1)
    _shimmer(b, (84, 88, 91, 96), 0.0, 0.07, 0.6, 0.18)
    put(b, tone(mtof(72), 0.8, SOFT, tau=0.3), 0.05, 0.35)
    return norm(b, 0.42)


def sfx_coop_link(r):
    """Amico collegato / sessione co-op: due note a quinta, calde, che si rispondono."""
    b = silence(1.3)
    put(b, tone(mtof(67), 0.7, SOFT, tau=0.3), 0.0, 0.8)
    put(b, tone(mtof(74), 0.8, SOFT, tau=0.35), 0.18, 0.8)
    put(b, tone(mtof(79), 0.8, BELL, tau=0.3), 0.36, 0.5)
    return room(norm(b, 0.45), r, 0.5, 0.25)


# ------------------------------------------------------------------ effetti: 17 mansioni x 3 varianti
PV = {1: 1.0, 2: 1.12, 3: 0.89}          # fattore di tono per variante (evita l'effetto 'mitragliatrice')


def _wood(v, r):
    p = PV[v]
    b = silence(0.55)
    put(b, tone(190 * p, 0.22, WOOD, tau=0.05, sweep=0.9), 0.0)                  # tonfo dell'ascia
    put(b, noise_band(0.12, 500, 2200, r, 0.03), 0.0, 0.55)                       # schegge
    put(b, noise_band(0.05, 1800, 4500, r, 0.01), 0.0, 0.2)
    put(b, tone(115 * p, 0.3, (1.0, 0.4), tau=0.1), 0.05, 0.3)                    # risonanza del tronco
    if v == 2:
        put(b, tone(150 * p, 0.12, WOOD, tau=0.03, sweep=0.8), 0.17, 0.6)
    return norm(b, 0.4)


def _mine(v, r):
    p = PV[v]
    b = silence(0.7)
    put(b, inharm(1500 * p, 0.35, 0.07, (1.0, 1.6, 2.76), (1.0, 0.4, 0.25)), 0.0, 0.5)   # clink metallico
    put(b, noise_band(0.1, 900, 3200, r, 0.025), 0.0, 0.5)                         # roccia che salta
    put(b, tone(95 * p, 0.2, (1.0, 0.5), tau=0.06, sweep=1.0), 0.0, 0.7)           # colpo sordo
    put(b, inharm(1500 * p, 0.3, 0.09, (1.0, 1.6, 2.76), (1.0, 0.4, 0.25)), 0.19, 0.18)   # eco lontana
    if v == 3:
        put(b, crackle(0.2, 120, r, 1500, 5000, 0.06), 0.06, 0.25)              # sassolini
    return norm(b, 0.4)


def _fish(v, r):
    p = PV[v]
    b = silence(0.8)
    put(b, noise_sweep(0.22, 1200 * p, 400, r, 0.7, None, 0.03, 8, 0.05), 0.0, 0.3)  # lenza che sibila
    put(b, blip(300 * p, 750 * p, 0.12, 0.05), 0.24, 0.6)                          # plop
    put(b, noise_sweep(0.3, 3500, 1200, r, 0.8, 0.1, 0.004, 8), 0.24, 0.35)         # spruzzo
    if v == 3:
        put(b, blip(420, 900, 0.08, 0.03), 0.42, 0.35)
    return norm(b, 0.38)


def _forage(v, r):
    p = PV[v]
    b = silence(0.5)
    put(b, noise_sweep(0.18, 2500 * p, 5200 * p, r, 0.9, None, 0.02, 8, 0.05), 0.0, 0.6)  # falcetto che fruscia
    put(b, crackle(0.3, 260, r, 2000, 7000, 0.1), 0.02, 0.5)                       # steli che si spezzano
    put(b, tone(310 * p, 0.1, (1.0, 0.3), tau=0.03), 0.02, 0.25)
    if v == 2:
        put(b, noise_sweep(0.12, 3000, 6000, r, 0.9, None, 0.01, 6), 0.2, 0.35)
    return norm(b, 0.36)


def _trap(v, r):
    p = PV[v]
    b = silence(0.55)
    put(b, tone(900 * p, 0.04, (1.0, 0.5), tau=0.01), 0.0, 0.8)                    # scatto
    put(b, noise_band(0.03, 1500, 5000, r, 0.006), 0.0, 0.5)
    put(b, tone(700 * p, 0.35, (1.0, 0.3), tau=0.12, sweep=-0.45, vib=0.4), 0.03, 0.4)   # molla che vibra
    put(b, tone(130 * p, 0.12, WOOD, tau=0.04), 0.07, 0.6)                          # legno sul legno
    if v == 3:
        put(b, tone(850 * p, 0.03, (1.0, 0.5), tau=0.01), 0.14, 0.4)
    return norm(b, 0.4)


def _smith(v, r):
    p = PV[v]
    b = silence(0.8)
    put(b, tone(140 * p, 0.15, (1.0, 0.5), tau=0.04, sweep=0.8), 0.0, 0.8)          # martello
    put(b, inharm(820 * p, 0.6, 0.18, (1.0, 2.32, 4.25, 6.63), (1.0, 0.6, 0.35, 0.2)), 0.0, 0.6)   # incudine che suona
    put(b, noise_band(0.04, 2500, 6000, r, 0.01), 0.0, 0.3)
    if v == 2:
        put(b, inharm(820 * p, 0.4, 0.12, (1.0, 2.32, 4.25), (1.0, 0.5, 0.3)), 0.2, 0.5)
        put(b, tone(160 * p, 0.1, (1.0, 0.5), tau=0.03, sweep=0.8), 0.2, 0.5)
    return norm(b, 0.4)


def _woodwork(v, r):
    p = PV[v]
    b = silence(0.7)
    for i in range(2 + (v == 3)):                                                   # colpi di sega avanti/indietro
        d = 0.2
        t = tvec(d)
        n = noise_band(d, 1200 * p, 4500, r, 1.0, 0.02) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t))
        put(b, fade(n * np.sin(np.pi * t / d), 0.01, 0.03), 0.02 + 0.22 * i, 0.55)
        put(b, tone(210 * p * (1 + 0.1 * i), d, (1.0, 0.6, 0.4), tau=1.0, attack=0.03), 0.02 + 0.22 * i, 0.12)
    return norm(b, 0.34)


def _tailor(v, r):
    p = PV[v]
    b = silence(0.55)
    for i in range(2):                                                              # due 'shing' di forbici
        put(b, noise_sweep(0.1, 4500, 8500 * p, r, 0.5, 0.05, 0.004, 5, 0.03), 0.0 + 0.12 * i, 0.35)
        put(b, inharm(2700 * p, 0.12, 0.04, (1.0, 1.5), (1.0, 0.5)), 0.01 + 0.12 * i, 0.3)
    put(b, noise_sweep(0.25, 900, 2500, r, 0.9, None, 0.05, 6, 0.08), 0.1, 0.2)    # stoffa
    if v == 3:
        put(b, noise_sweep(0.1, 4500, 8000, r, 0.5, 0.05, 0.004, 5, 0.03), 0.3, 0.3)
    return norm(b, 0.34)


def _cook(v, r):
    p = PV[v]
    b = silence(0.8)
    put(b, noise_band(0.7, 1800 * p, 6000, r, 0.35, 0.03), 0.0, 0.5)               # sfrigolio
    put(b, crackle(0.7, 90 + 30 * v, r, 600, 3200, 0.45), 0.0, 0.7)                 # schizzi d'olio
    put(b, inharm(520 * p, 0.2, 0.05, (1.0, 2.1, 3.7), (1.0, 0.4, 0.2)), 0.0, 0.3)   # clang della padella
    return norm(b, 0.34)


def _alchemy(v, r):
    p = PV[v]
    b = silence(0.8)
    starts = (0.0, 0.11, 0.2, 0.34) if v != 2 else (0.0, 0.07, 0.19, 0.3, 0.41)
    for i, s in enumerate(starts):
        f = (320 + 130 * ((i * 3 + v) % 4)) * p
        put(b, blip(f, f * 2.0, 0.09, 0.04), s, 0.55)
    put(b, inharm(2200 * p, 0.35, 0.12, (1.0, 2.4), (1.0, 0.3)), 0.12, 0.28)        # tintinnio di vetro
    put(b, noise_band(0.5, 2500, 6000, r, 0.18, 0.05), 0.0, 0.1)
    return norm(b, 0.36)


def _jewel(v, r):
    p = PV[v]
    b = silence(0.7)
    put(b, tone(2400 * p, 0.03, (1.0, 0.4), tau=0.007), 0.0, 0.6)                   # punta dello scalpello
    put(b, inharm(3100 * p, 0.55, 0.16, (1.0, 2.0, 3.01), (1.0, 0.35, 0.15)), 0.0, 0.55)   # gemma che canta
    put(b, noise_band(0.03, 3000, 7000, r, 0.006), 0.0, 0.3)
    if v == 2:
        put(b, inharm(4150 * p, 0.4, 0.12, (1.0, 2.0), (1.0, 0.3)), 0.12, 0.35)
    if v == 3:
        put(b, inharm(2600 * p, 0.4, 0.12, (1.0, 2.0), (1.0, 0.3)), 0.1, 0.35)
    return norm(b, 0.34)


def _rune(v, r):
    p = PV[v]
    b = silence(0.8)
    put(b, noise_sweep(0.25, 1200, 3600 * p, r, 0.7, None, 0.03, 8, 0.06), 0.0, 0.45)   # incisione
    for i, m in enumerate((74, 81, 86)):                                                 # bagliore magico
        put(b, tone(mtof(m + (v - 1) * 2), 0.5, (1.0, 0.2), tau=0.2, vib=0.6), 0.16 + 0.07 * i, 0.4)
    return norm(b, 0.34)


def _key(v, r):
    p = PV[v]
    b = silence(0.7)
    for i in range(3):                                                              # colpi di lima
        t0 = 0.16 * i
        put(b, noise_sweep(0.11, 2200, 6500 * p, r, 0.8, None, 0.01, 6, 0.03) * (0.6 + 0.4 * np.sin(np.arange(int(0.11 * SR)) / SR * 2 * np.pi * 70)), t0, 0.45)
    put(b, inharm(2000 * p, 0.3, 0.1, (1.0, 1.7, 2.9), (1.0, 0.5, 0.3)), 0.5 if v != 2 else 0.45, 0.35)   # chiave che tintinna
    return norm(b, 0.34)


def _thief(v, r):
    p = PV[v]
    b = silence(0.7)
    put(b, noise_sweep(0.15, 600, 1800, r, 0.9, None, 0.03, 6, 0.05), 0.0, 0.3)     # fruscio del mantello
    for i, s in enumerate((0.1, 0.17, 0.3)[: 2 + (v == 3)]):                        # monete tintinnano piano
        put(b, inharm((2500 + 400 * i) * p, 0.25, 0.07, (1.0, 1.5, 2.2), (1.0, 0.4, 0.2)), s, 0.5)
    return norm(b, 0.32)


def _farm(v, r):
    p = PV[v]
    b = silence(0.6)
    put(b, tone(110 * p, 0.2, (1.0, 0.4), tau=0.07, sweep=0.7), 0.0, 0.9)           # zappa nel terreno
    put(b, noise_band(0.18, 150, 900, r, 0.07), 0.0, 0.6)
    put(b, crackle(0.2, 200, r, 800, 3500, 0.07), 0.06, 0.4)                        # zolle
    if v == 3:
        put(b, tone(120 * p, 0.12, (1.0, 0.4), tau=0.05, sweep=0.7), 0.2, 0.5)
    return norm(b, 0.38)


def _hero(v, r):
    p = PV[v]
    b = silence(0.6)
    put(b, noise_sweep(0.16, 500, 3500 * p, r, 0.9, None, 0.02, 8, 0.04), 0.0, 0.5)   # fendente
    put(b, inharm(1100 * p, 0.35, 0.09, (1.0, 2.76, 5.4), (1.0, 0.4, 0.2)), 0.14, 0.5)   # clangore
    put(b, tone(130 * p, 0.12, (1.0, 0.4), tau=0.04, sweep=0.8), 0.14, 0.6)
    return norm(b, 0.4)


def _bounty(v, r):
    p = PV[v]
    b = silence(0.8)
    put(b, tone(100 * p, 0.14, (1.0, 0.5), tau=0.04, sweep=0.7), 0.0, 0.9)          # timbro che batte
    put(b, noise_band(0.08, 400, 2500, r, 0.02), 0.0, 0.45)                         # carta
    put(b, tone(mtof(67 + 2 * (v - 1)), 0.5, BELL, tau=0.18), 0.12, 0.5)            # campanello
    put(b, tone(mtof(74 + 2 * (v - 1)), 0.5, BELL, tau=0.16), 0.2, 0.35)
    return norm(b, 0.36)


SKILL_SFX = {"woodcutting": _wood, "mining": _mine, "fishing": _fish, "foraging": _forage, "trapping": _trap,
             "smithing": _smith, "woodworking": _woodwork, "tailoring": _tailor, "cooking": _cook,
             "alchemy": _alchemy, "jewelcrafting": _jewel, "runecarving": _rune, "keysmithing": _key,
             "thievery": _thief, "farming": _farm, "hero": _hero, "bounty": _bounty}

SFX = {k[4:]: v for k, v in list(globals().items()) if k.startswith("sfx_")}
for _sk, _fn in SKILL_SFX.items():
    for _v in (1, 2, 3):
        SFX["sk_%s_%d" % (_sk, _v)] = (lambda r, _fn=_fn, _v=_v: _fn(_v, r))


# ------------------------------------------------------------------ musica (loop morbidi, stereo)
MODES = {
    "ionian": (0, 2, 4, 5, 7, 9, 11), "dorian": (0, 2, 3, 5, 7, 9, 10), "phrygian": (0, 1, 3, 5, 7, 8, 10),
    "lydian": (0, 2, 4, 6, 7, 9, 11), "mixolydian": (0, 2, 4, 5, 7, 9, 10), "aeolian": (0, 2, 3, 5, 7, 8, 10),
    "harmonic": (0, 2, 3, 5, 7, 8, 11), "wholetone": (0, 2, 4, 6, 8, 10, 11),
}


class Loop2:
    """Buffer stereo circolare: ciò che esce dalla fine rientra dall'inizio (loop senza click)."""

    def __init__(self, seconds):
        self.n = int(round(seconds * SR))
        self.buf = np.zeros((self.n, 2))

    def add(self, sig, at, gain=1.0, pan=0.0):
        i = int(at * SR) % self.n
        a = (pan + 1.0) * np.pi / 4.0                        # pan a potenza costante
        gl, gr = np.cos(a) * gain, np.sin(a) * gain
        s = sig
        while len(s):
            k = min(len(s), self.n - i)
            self.buf[i:i + k, 0] += s[:k] * gl
            self.buf[i:i + k, 1] += s[:k] * gr
            s = s[k:]
            i = 0


# ---- strumenti (tutti sintesi additiva morbida; niente armoniche alte: l'ascolto dura ore)
def pluck(f, dur, tau=0.5, bright=0.6):
    """Corda pizzicata (liuto/arpa/chitarra): ogni armonica decade più in fretta della precedente."""
    t = tvec(dur)
    y = np.zeros_like(t)
    for k in range(1, 8):
        fk = f * k * (1 + 0.0004 * k * k)
        if fk > 8000:
            break
        y += (bright ** (k - 1)) / k ** 0.8 * np.sin(2 * np.pi * fk * t) * np.exp(-t / (tau / (1 + 0.7 * (k - 1))))
    return fade(y * np.minimum(1.0, t / 0.003) * 0.7, 0.003, min(0.08, dur * 0.3))


def pad(f, dur, harm=(1.0, 0.2), attack=0.9, release=1.0, detune=0.003, ph=0.0, trem=0.0):
    return sustained(f, dur, harm, attack, release, trem, detune, ph)


def lead(f, dur, harm=(1.0, 0.18, 0.06), attack=0.07, release=0.3, vib=0.0035, breath=0.02, rng=None):
    """Flauto/ottone dolce/fisarmonica con vibrato che entra lentamente."""
    t = tvec(dur)
    ramp = np.minimum(1.0, np.maximum(0.0, t - 0.15) / 0.4)
    ph = 2 * np.pi * f * t + (f * vib / 5.3) * ramp * np.sin(2 * np.pi * 5.3 * t)      # vibrato che entra piano
    y = sum(a * np.sin((k + 1) * ph) for k, a in enumerate(harm))
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, np.maximum(0.0, dur - t) / release)
    y = y * env / max(1.0, sum(harm) * 0.8)
    if breath and rng is not None:
        y = y + breath * noise_band(dur, 1800, 4200, rng, 10.0, 0.05) * env
    return y


def strings(f, dur, attack=0.5, release=0.6, trem=0.0):
    return sustained(f, dur, (1.0, 0.45, 0.28, 0.18, 0.1), attack, release, trem, 0.004)


def choir(f, dur, attack=1.3, release=1.3, ph=0.0):
    t = tvec(dur)
    y = np.zeros_like(t)
    for d in (-0.004, 0.0, 0.0045):
        v = 2 * np.pi * f * (1 + d) * t + (f * 0.003 / 5.4) * np.sin(2 * np.pi * 5.4 * t + ph + d * 300)
        for k, a in enumerate((1.0, 0.12, 0.55, 0.3, 0.14, 0.06), 1):
            y += a * np.sin(k * v + ph)
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, np.maximum(0.0, dur - t) / release)
    return y * env / 8.0


def bell(f, dur, tau=0.9):
    return inharm(f, dur, tau, (1.0, 2.0, 2.76, 4.07), (1.0, 0.35, 0.3, 0.12), 0.002)


def celesta(f, dur, tau=0.5):
    return tone(f, dur, (1.0, 0.0, 0.0, 0.35, 0.0, 0.0, 0.1), tau=tau, attack=0.002)


def vibes(f, dur, tau=0.9):
    t = tvec(dur)
    return tone(f, dur, (1.0, 0.0, 0.0, 0.0, 0.25), tau=tau) * (1.0 + 0.22 * np.sin(2 * np.pi * 5.0 * t))


def taiko(dur=0.6, f=58.0):
    return tone(f, dur, (1.0, 0.5, 0.2), tau=0.2, sweep=1.4, attack=0.002)


def shaker(rng, dur=0.07):
    return noise_band(dur, 4500, 8500, rng, 0.02, 0.004)


def soft_pulse(f, dur):
    return tone(f, dur, (1.0, 0.3), tau=dur * 0.4, attack=0.01)


class Track:
    """Una traccia: tempo, tonalità, progressione e generatore di melodia riproducibile (seme dal nome)."""

    def __init__(self, sp):
        self.sp = sp
        self.beat = 60.0 / sp["bpm"]
        self.e = self.beat / 2.0
        self.bar = 4.0 * self.beat
        self.bars = sp["bars"]
        self.r = rng_for(sp["name"])
        self.L = Loop2(self.bar * self.bars)
        self.scale = MODES[sp["mode"]]
        self.mel = self._melody()

    @property
    def dur(self):
        return self.bar * self.bars

    def note(self, deg, octv=0):
        o, i = divmod(deg, 7)
        return self.sp["root"] + self.scale[i] + 12 * (o + octv)

    def prog(self, b):
        return self.sp["prog"][b % len(self.sp["prog"])]

    def chord(self, b, seventh=False):
        d = self.prog(b)
        n = [self.note(d), self.note(d + 2), self.note(d + 4)]
        return d, n + ([self.note(d + 6)] if seventh else [])

    def bass(self, b, octv=-2, fifth=False):
        return self.note(self.prog(b) + (4 if fifth else 0), octv)

    def _melody(self):
        """Frasi di due battute (A, B) riusate in modo A B A B' -> coerenza senza ripetizione meccanica."""
        r = self.r
        rhythms = ((0, 3, 4, 6), (0, 2, 4, 5), (1, 3, 4, 7), (0, 4, 6), (0, 2, 3, 6), (0, 3, 6))
        deg = 7 + int(r.integers(0, 4))
        phrases = []
        for _ in range(2):
            ph = []
            for bi in range(2):
                for pos in rhythms[int(r.integers(0, len(rhythms)))]:
                    deg = int(np.clip(deg + int(r.integers(-2, 3)), 5, 13))
                    ph.append((bi, pos, deg, 2 if int(r.integers(0, 3)) == 0 else 1))
            phrases.append(ph)
        out = []
        for b in range(self.bars):
            ph = phrases[(b // 2) % 2]
            for bi, pos, deg, ln in ph:
                if bi != b % 2:
                    continue
                d = deg
                if (b // 2) % 4 == 3 and pos == ph[-1][1]:
                    d = deg + 1                       # B': finale variato
                if pos in (0, 4):                    # tempi forti: vicino a una nota dell'accordo
                    ch = [(self.prog(b) + k) % 7 for k in (0, 2, 4)]
                    d = min((d + s for s in (0, -1, 1, -2, 2) if (d + s) % 7 in ch), key=lambda x: abs(x - d))
                out.append((b, pos, d, ln))
        return out

    def play_melody(self, make, gain, pan, mask=(1, 1, 0, 1), octv=0, density=1.0):
        """make(freq, durata) -> segnale. mask: battute in cui la melodia suona (si ripete)."""
        for b, pos, deg, ln in self.mel:
            if not mask[b % len(mask)] or (density < 1.0 and self.r.random() > density):
                continue
            d = ln * self.e * (1.3 if ln > 1 else 1.0)
            self.L.add(make(mtof(self.note(deg, octv)), d), b * self.bar + pos * self.e, gain, pan)


# ---- stili
def st_menu(c):
    pat = c.sp.get("pat", 0)
    order = ((0, 1, 2, 3, 2, 1, 2, 1), (0, 2, 1, 3, 1, 2, 3, 2), (0, 1, 2, 1, 3, 2, 1, 2))[pat % 3]
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        ar = ch + [ch[0] + 12]
        for k in range(8):
            c.L.add(pluck(mtof(ar[order[k]] + 12 * (k % 8 == 7)), 1.6, 0.6), t0 + k * c.e, 0.30, -0.3 + 0.12 * (k % 3))
        c.L.add(pluck(mtof(c.bass(b)), 2.2, 1.0, 0.5), t0, 0.40, -0.05)
        c.L.add(pluck(mtof(c.bass(b, -2, True)), 1.6, 0.8, 0.5), t0 + 2 * c.beat, 0.28, 0.05)
        for j, m in enumerate(ch):
            for s, pn in ((0.0, -0.6), (1.7, 0.6)):
                c.L.add(pad(mtof(m - 12), c.bar + 1.2, (1.0, 0.2), 1.0, 1.2, 0.003, s), t0 - 0.2, 0.05, pn)
    c.play_melody(lambda f, d: lead(f, d, (1.0, 0.15), 0.08, 0.5, rng=c.r), 0.22, 0.45, (1, 1, 0, 1))


def st_skilling(c):
    pat = c.sp.get("pat", 0)
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        ar = [ch[0], ch[1], ch[2], ch[0] + 12, ch[1] + 12, ch[2] + 12, ch[1] + 12, ch[0] + 12]
        if pat == 1:
            ar = ar[::-1]
        for k in range(8):
            c.L.add(pluck(mtof(ar[k] + 12), 1.8, 0.7, 0.45), t0 + k * c.e, 0.27 if k % 4 else 0.34, -0.4 + 0.11 * k)
        for k in (0, 2):
            c.L.add(pluck(mtof(c.bass(b)), 0.9, 0.35, 0.5), t0 + k * c.beat, 0.34 - 0.06 * k, 0.0)
        if b % 2 == 0:
            for m in ch:
                c.L.add(pad(mtof(m), c.bar * 2 + 0.8, (1.0, 0.15), 1.4, 1.4, 0.004, 0.7 * m), t0 - 0.3, 0.04, 0.5 if m % 2 else -0.5)
    c.play_melody(lambda f, d: pluck(f, d + 0.6, 0.6, 0.35), 0.24, 0.3, (0, 1, 1, 0), 1)


def st_combat_early(c):
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        for k in range(8):
            if k % 4 == 0:
                c.L.add(taiko(0.5), t0 + k * c.e, 0.34, 0.0)
            elif k == 6:
                c.L.add(taiko(0.35, 80), t0 + k * c.e, 0.2, 0.1)
            c.L.add(shaker(c.r), t0 + k * c.e, 0.05 if k % 2 else 0.08, 0.35 if k % 2 else -0.35)
            c.L.add(pluck(mtof(c.bass(b)), 0.45, 0.18, 0.7), t0 + k * c.e, 0.2 if k % 2 == 0 else 0.12, 0.0)
        for j, m in enumerate(ch):
            c.L.add(strings(mtof(m), c.bar + 0.3, 0.4, 0.5, 0.06), t0, 0.06, -0.5 + 0.5 * j)
    c.play_melody(lambda f, d: lead(f, d, (1.0, 0.5, 0.3, 0.15), 0.1, 0.2, 0.002, 0.0), 0.15, 0.2, (0, 1, 1, 1))
    c.play_melody(lambda f, d: pluck(f, d + 0.3, 0.3, 0.6), 0.14, -0.3, (1, 0, 1, 0), 1)


def st_combat_mid(c):
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        for k in range(8):
            if k in (0, 3, 4):
                c.L.add(taiko(0.55, 52), t0 + k * c.e, 0.4 if k == 0 else 0.26, 0.0)
            c.L.add(strings(mtof(c.bass(b, -1)), c.e * 0.95, 0.03, 0.06), t0 + k * c.e, 0.11 if k % 2 else 0.15, -0.2)
            c.L.add(shaker(c.r, 0.05), t0 + k * c.e + (c.e / 2 if k % 2 else 0), 0.035, 0.4)
        for m in ch:
            c.L.add(strings(mtof(m - 12), c.bar + 0.4, 0.5, 0.6, 0.1), t0, 0.075, -0.4)
            c.L.add(strings(mtof(m), c.bar + 0.4, 0.8, 0.6, 0.0), t0, 0.04, 0.4)
        if b % 4 == 3:
            c.L.add(bell(mtof(c.note(c.prog(b) + 8)), 2.5, 1.2), t0 + c.beat * 2, 0.15, 0.6)
    c.play_melody(lambda f, d: strings(f, d + 0.3, 0.06, 0.3, 0.1), 0.11, 0.3, (0, 0, 1, 0), 0)


def st_combat_late(c):
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b, True)
        c.L.add(taiko(1.0, 48), t0, 0.62, 0.0)
        if b % 2 == 1:
            c.L.add(taiko(0.6, 62), t0 + 2 * c.beat, 0.34, 0.1)
        for j, m in enumerate(ch):
            c.L.add(choir(mtof(m), c.bar * 1.15, 1.2, 1.2, 0.8 * j), t0 - 0.1, 0.075, -0.6 + 0.4 * j)
            c.L.add(strings(mtof(m + 12), c.bar + 0.2, 0.3, 0.4, 0.2), t0, 0.04, 0.6 - 0.4 * j)
        for k in range(8):
            m = ch[(k * 3 + b) % len(ch)] + 24
            c.L.add(bell(mtof(m), 1.3, 0.5), t0 + k * c.e, 0.085, -0.7 + 0.2 * (k % 8))
        c.L.add(pad(mtof(c.bass(b, -2)), c.bar + 0.4, (1.0, 0.5), 0.2, 0.5, 0.002), t0, 0.17, 0.0)
    c.play_melody(lambda f, d: lead(f, d, (1.0, 0.4, 0.2, 0.1), 0.15, 0.4, 0.004, 0.0), 0.12, 0.0, (1, 1, 0, 1), 0)


def st_dungeon(c):
    for b in range(c.bars):
        t0 = b * c.bar
        d, ch = c.chord(b)
        if b % 2 == 0:
            for j, m in enumerate((ch[0] - 24, ch[0] - 12, ch[2] - 12)):
                for s, pn in ((0.0, -0.7), (2.3, 0.7)):
                    c.L.add(pad(mtof(m), c.bar * 2 + 1.5, (1.0, 0.4, 0.2), 1.8, 1.8, 0.0035 * (j + 1), s), t0 - 0.5, 0.075, pn)
        if b % 3 == 0:
            c.L.add(soft_pulse(mtof(ch[0] - 24), c.beat * 1.2), t0, 0.28, 0.0)
            c.L.add(soft_pulse(mtof(ch[0] - 24), c.beat * 1.2), t0 + c.beat * 0.7, 0.18, 0.0)
        if c.r.random() < 0.65:
            m = c.note(int(c.r.integers(7, 14)), 1)
            c.L.add(bell(mtof(m), 3.5, 1.5), t0 + c.beat * float(c.r.integers(0, 6)) / 2.0, 0.17, float(c.r.uniform(-0.85, 0.85)))
        if b % 4 == 2:
            c.L.add(strings(mtof(ch[1]), c.bar * 1.3, 1.5, 1.5, 0.15), t0, 0.04, 0.3)


def st_boss(c):
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        swell = 0.7 + 0.3 * np.sin(np.pi * b / c.bars) ** 2        # crescendo controllato e poi calo: il loop resta uniforme
        for k in range(8):
            c.L.add(pluck(mtof(c.bass(b, -2)), 0.4, 0.14, 0.7), t0 + k * c.e, (0.22 if k % 2 == 0 else 0.13) * swell, 0.0)
            if k % 2 == 0:
                c.L.add(taiko(0.42, 56), t0 + k * c.e, (0.36 if k == 0 else 0.25) * swell, 0.0)
        c.L.add(taiko(0.3, 90), t0 + 3 * c.e, 0.18 * swell, 0.2)
        c.L.add(taiko(0.3, 90), t0 + 7 * c.e, 0.2 * swell, -0.2)
        for j, m in enumerate(ch):
            for k in (0, 3 if b % 2 else 2):
                c.L.add(lead(mtof(m), c.beat * 1.3, (1.0, 0.7, 0.5, 0.3, 0.18), 0.07, 0.25, 0.0, 0.0), t0 + k * c.beat, 0.08 * swell, -0.4 + 0.4 * j)
            c.L.add(strings(mtof(m - 12), c.bar + 0.2, 0.2, 0.3, 0.12), t0, 0.06 * swell, 0.0)
        c.L.add(shaker(c.r, 0.05), t0 + c.e * 3, 0.07, 0.5)
    c.play_melody(lambda f, d: lead(f, d, (1.0, 0.6, 0.35, 0.2), 0.08, 0.2, 0.003, 0.0), 0.13, 0.15, (1, 1, 1, 0), 0)


def st_rift(c):
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        if b % 2 == 0:
            for j, m in enumerate(ch):
                for s, pn in ((0.0, -0.8), (2.1, 0.8)):
                    c.L.add(pad(mtof(m - 12 * (j == 0)), c.bar * 2 + 1.6, (1.0, 0.3, 0.12), 1.8, 1.8, 0.006 + 0.002 * j, s, 0.35), t0 - 0.5, 0.06, pn)
        for k in range(int(c.r.integers(3, 7))):                               # scintille di vetro casuali (ma riproducibili)
            m = c.note(int(c.r.integers(10, 17)))
            c.L.add(celesta(mtof(m), 1.6, 0.7), t0 + float(c.r.uniform(0, c.bar)), 0.1, float(c.r.uniform(-0.9, 0.9)))
        sub = soft_pulse(mtof(c.bass(b, -3)), c.bar * 0.5)
        c.L.add(sub, t0, 0.3, 0.0)
        c.L.add(sub, t0 + c.bar * 0.5, 0.2, 0.0)
        if b % 4 == 1:
            c.L.add(noise_sweep(c.bar * 0.9, 400, 2400, c.r, 0.5, None, c.bar * 0.4, 7, c.bar * 0.4), t0, 0.05, float(c.r.uniform(-0.6, 0.6)))
    c.play_melody(lambda f, d: vibes(f, d + 0.8, 1.1), 0.12, -0.2, (0, 1, 0, 0), 1, 0.6)


def st_estate(c):
    pat = (0, 1, 2, 1, 0, 2, 1, 2)
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        for k, p in enumerate(pat):
            c.L.add(pluck(mtof(ch[p % 3]), 1.3, 0.45, 0.55), t0 + k * c.e, 0.27, -0.3 + 0.1 * (k % 4))
        c.L.add(pluck(mtof(c.bass(b)), 1.0, 0.5, 0.45), t0, 0.40, 0.0)
        c.L.add(pluck(mtof(c.bass(b, -2, True)), 0.8, 0.4, 0.45), t0 + 2 * c.beat, 0.30, 0.0)
        for m in ch:
            c.L.add(sustained(mtof(m), c.bar * 0.95, (1.0, 0.5, 0.3, 0.2, 0.1), 0.25, 0.4, 0.12), t0, 0.04, 0.35)
    c.play_melody(lambda f, d: lead(f, d, (1.0, 0.3, 0.15), 0.06, 0.35, 0.003, 0.012, c.r), 0.18, 0.3, (0, 1, 0, 1))


def st_prestige(c):
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b, True)
        for j, m in enumerate(ch):
            c.L.add(choir(mtof(m), c.bar * 1.25, 1.6, 1.6, 0.9 * j), t0 - 0.3, 0.075, -0.55 + 0.35 * j)
        c.L.add(pad(mtof(c.bass(b, -2)), c.bar + 0.8, (1.0, 0.4), 0.8, 0.9, 0.002), t0, 0.2, 0.0)
        for k in range(8):
            m = ch[k % len(ch)] + 12 + 12 * (k // 4)
            c.L.add(pluck(mtof(m), 2.2, 1.0, 0.45), t0 + k * c.e, 0.14 + 0.01 * k, -0.6 + 0.17 * k)
        if b % 2 == 0:
            c.L.add(bell(mtof(ch[0] + 24), 3.5, 1.6), t0, 0.1, 0.4)
    c.play_melody(lambda f, d: lead(f, d + 0.4, (1.0, 0.22, 0.08), 0.2, 0.6, 0.004, 0.0), 0.15, 0.1, (1, 0, 1, 1), 0)


def st_vault(c):
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        for k in range(8):
            if (k + b) % 3 != 2:
                m = (ch + [ch[0] + 12, ch[1] + 12])[(k * 2 + b) % 5] + 24
                c.L.add(celesta(mtof(m), 1.3, 0.55), t0 + k * c.e, 0.17, -0.7 + 0.2 * (k % 8))
        for k in (0, 4):
            c.L.add(vibes(mtof(c.bass(b, 0)), 2.5, 1.4), t0 + k * c.e, 0.16, 0.5 if k else -0.5)
        for m in ch:
            c.L.add(pad(mtof(m - 12), c.bar + 1.0, (1.0, 0.25), 1.0, 1.2, 0.003, 0.6 * m, 0.25), t0 - 0.2, 0.06, 0.0)
        c.L.add(soft_pulse(mtof(c.bass(b, -3)), c.beat * 1.5), t0, 0.26, 0.0)
    c.play_melody(lambda f, d: vibes(f, d + 0.8, 1.2), 0.17, 0.3, (1, 0, 1, 1), 1)


def st_event(c):
    for b in range(c.bars):
        t0 = b * c.bar
        _, ch = c.chord(b)
        for k in range(4):
            if k % 2 == 0:
                c.L.add(pluck(mtof(c.bass(b, -2, k == 2)), 0.5, 0.2, 0.6), t0 + k * c.beat, 0.38, 0.0)
            else:
                for m in ch:
                    c.L.add(pluck(mtof(m), 0.45, 0.2, 0.55), t0 + k * c.beat, 0.12, -0.3 + 0.3 * (m % 3))
            c.L.add(shaker(c.r, 0.05), t0 + k * c.beat + c.e, 0.05, 0.4)
        for m in ch:
            c.L.add(pad(mtof(m), c.bar + 0.4, (1.0, 0.5, 0.25), 0.3, 0.5, 0.003, 0.3 * m, 0.12), t0, 0.04, 0.0)
    c.play_melody(lambda f, d: lead(f, d, (1.0, 0.25, 0.1), 0.05, 0.25, 0.003, 0.02, c.r), 0.2, 0.2, (1, 1, 1, 1), 0)
    c.play_melody(lambda f, d: bell(f, 1.2, 0.35), 0.1, -0.4, (0, 1, 0, 1), 1, 0.7)


STYLES = {"menu": st_menu, "skilling": st_skilling, "combat_early": st_combat_early, "combat_mid": st_combat_mid,
          "combat_late": st_combat_late, "dungeon": st_dungeon, "boss": st_boss, "rift": st_rift,
          "estate": st_estate, "prestige": st_prestige, "vault": st_vault, "event": st_event}


# ---- livellamento (loudness stimata) e finitura
def k_weight(n):
    """Curva K semplificata: passa-alto sotto ~100 Hz, +4 dB sopra 2 kHz (stima, non norma ITU)."""
    fr = np.fft.rfftfreq(n, 1.0 / SR)
    hp = (fr / 100.0) ** 2 / (1.0 + (fr / 100.0) ** 2)
    shelf = 1.0 + 0.58 * (fr / 2000.0) ** 2 / (1.0 + (fr / 2000.0) ** 2)
    return hp * shelf


def loudness(x):
    """LUFS stimati del segnale (mono (n,) o stereo (n,2))."""
    x = x if x.ndim == 2 else x[:, None]
    p = 0.0
    for c in range(x.shape[1]):
        y = np.fft.irfft(np.fft.rfft(x[:, c]) * k_weight(len(x)), len(x))
        p += float(np.mean(y ** 2))
    return -0.691 + 10.0 * np.log10(max(p, 1e-12))


def circ_filter(x, f_hp=None, f_lp=None, order=2):
    """Filtri circolari via FFT (mantengono il loop senza giunzioni)."""
    n = len(x)
    fr = np.fft.rfftfreq(n, 1.0 / SR)
    h = np.ones_like(fr)
    if f_hp:
        h *= (fr / f_hp) ** (2 * order) / (1.0 + (fr / f_hp) ** (2 * order))
    if f_lp:
        h *= 1.0 / (1.0 + (fr / f_lp) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x, axis=0) * (h[:, None] if x.ndim == 2 else h), n, axis=0)


def circ_reverb(x, rng, rt=1.8, wet=0.3):
    """Riverbero a convoluzione circolare (coda di rumore che decade, due IR diverse = ampiezza stereo)."""
    n = len(x)
    fr = np.fft.rfftfreq(n, 1.0 / SR)
    out = np.zeros_like(x)
    li = int(rt * 1.4 * SR)
    for ch in range(2):
        ir = np.zeros(n)
        ir[:li] = rng.standard_normal(li) * np.exp(-np.arange(li) / SR / (rt / 6.9))
        ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
        IR = np.fft.rfft(ir) / (1.0 + (fr / 3200.0) ** 2) * (fr / 90.0) ** 2 / (1.0 + (fr / 90.0) ** 2)
        IR /= max(1e-9, np.sqrt(np.sum(np.abs(IR) ** 2) / len(IR)))
        src = x[:, ch] * 0.7 + x[:, 1 - ch] * 0.3
        out[:, ch] = np.fft.irfft(np.fft.rfft(src) * IR, n)
    return x * (1.0 - wet * 0.5) + out * wet * 0.55


def finish(x, target_lufs, ceiling=0.82):
    x = circ_filter(x, 38.0, 6200.0)
    for _ in range(3):                                        # livella, limita morbido, rilivella
        x = x * 10.0 ** ((target_lufs - loudness(x)) / 20.0)
        x = np.tanh(x / ceiling * 0.85) * ceiling / 0.85 * 0.9
    x = x * 10.0 ** ((target_lufs - loudness(x)) / 20.0)
    pk = np.max(np.abs(x))
    return x * (ceiling / pk) if pk > ceiling else x


MUSIC_LUFS = -22.0
ST = "stereo"
# (contesto, n.) -> parametri. Durata = battute x 4 x 60/bpm: 29-48 s. prog = gradi della scala (0 = tonica).
_S = lambda ctx, n, bpm, bars, root, mode, prog, **kw: dict(name="mus_%s_%d" % (ctx, n), ctx=ctx, bpm=bpm, bars=bars,
                                                          root=root, mode=mode, prog=prog, **kw)
MUSIC_SPECS = [
    _S("menu", 1, 72, 12, 57, "aeolian", [0, 5, 2, 6], pat=0),
    _S("menu", 2, 66, 8, 62, "dorian", [0, 3, 0, 4], pat=1),
    _S("menu", 3, 84, 12, 55, "mixolydian", [0, 6, 3, 0], pat=2),
    _S("skilling", 1, 80, 12, 60, "ionian", [0, 5, 3, 4], pat=0),
    _S("skilling", 2, 76, 12, 53, "lydian", [0, 1, 5, 4], pat=1),
    _S("skilling", 3, 88, 12, 57, "dorian", [0, 4, 3, 0], pat=0),
    _S("combat_early", 1, 108, 16, 50, "dorian", [0, 3, 0, 6]),
    _S("combat_early", 2, 112, 16, 55, "mixolydian", [0, 6, 3, 4]),
    _S("combat_mid", 1, 112, 16, 48, "phrygian", [0, 1, 0, 5]),
    _S("combat_mid", 2, 116, 16, 50, "harmonic", [0, 5, 3, 4]),
    _S("combat_late", 1, 120, 16, 55, "lydian", [0, 4, 1, 5]),
    _S("combat_late", 2, 116, 16, 52, "aeolian", [0, 5, 2, 6]),
    _S("dungeon", 1, 60, 10, 46, "phrygian", [0, 1]),
    _S("dungeon", 2, 54, 10, 43, "aeolian", [0, 5]),
    _S("boss", 1, 126, 16, 45, "harmonic", [0, 0, 5, 4]),
    _S("boss", 2, 120, 16, 50, "phrygian", [0, 1, 0, 6]),
    _S("rift", 1, 70, 12, 52, "wholetone", [0, 2, 4, 1]),
    _S("rift", 2, 64, 10, 50, "wholetone", [0, 3, 1, 4, 2]),
    _S("estate", 1, 76, 12, 55, "ionian", [0, 3, 4, 0]),
    _S("estate", 2, 88, 12, 62, "mixolydian", [0, 6, 3, 0]),
    _S("prestige", 1, 56, 8, 57, "lydian", [0, 5, 3, 4]),
    _S("prestige", 2, 60, 8, 55, "ionian", [0, 4, 5, 3]),
    _S("vault", 1, 84, 12, 60, "aeolian", [0, 2, 5, 3]),
    _S("vault", 2, 78, 12, 57, "dorian", [0, 6, 3, 4]),
    _S("event", 1, 104, 16, 50, "ionian", [0, 3, 4, 0]),
    _S("event", 2, 100, 16, 55, "mixolydian", [0, 6, 3, 0]),
]
REVERB = {"menu": (1.6, 0.30), "skilling": (1.8, 0.32), "combat_early": (1.0, 0.18), "combat_mid": (1.3, 0.22),
          "combat_late": (2.2, 0.34), "dungeon": (3.0, 0.45), "boss": (1.2, 0.2), "rift": (3.2, 0.45),
          "estate": (1.4, 0.26), "prestige": (2.8, 0.4), "vault": (2.4, 0.38), "event": (1.2, 0.22)}


def render_track(sp):
    c = Track(sp)
    assert 24.0 <= c.dur <= 48.0, (sp["name"], c.dur)
    STYLES[sp["ctx"]](c)
    rt, wet = REVERB[sp["ctx"]]
    y = circ_reverb(c.L.buf, rng_for(sp["name"] + "rv"), rt, wet)
    return finish(y, MUSIC_LUFS)


MUSIC = {sp["name"]: (lambda sp=sp: render_track(sp)) for sp in MUSIC_SPECS}


# ------------------------------------------------------------------ scrittura
SKILL_LUFS = -25.5
# Categorie degli effetti e loudness stimata di riferimento (LUFS~): i suoni brevi e frequenti (UI, commercio) un po' piu'
# forti perche' durano poco, gli stinger lunghi piu' piano; le rivelazioni salgono di rarita' (+0,5 dB per grado).
SFX_TARGET_LUFS = {"ui": -20.5, "combat": -22.5, "stinger": -22.5}
SFX_REVEAL_LUFS = {"reveal_rare": -24.5, "reveal_epic": -24.0, "reveal_legendary": -23.5, "reveal_mythic": -23.0,
                   "reveal_relic": -22.5}
SFX_UI = ("ui_click", "ui_confirm", "ui_error", "ui_notify", "ui_unlock", "action_done", "coin", "sell", "buy",
          "reel_tick", "crate_found", "drop_rare")
SFX_COMBAT = ("hit", "hit_crit", "dodge", "hurt", "kill")


def sfx_category(name):
    if name.startswith("sk_"):
        return "skill"
    if name in SFX_UI:
        return "ui"
    if name in SFX_COMBAT:
        return "combat"
    return "stinger"


def sfx_target(name):
    cat = sfx_category(name)
    if name in SFX_REVEAL_LUFS:
        return SFX_REVEAL_LUFS[name]
    return SKILL_LUFS if cat == "skill" else SFX_TARGET_LUFS[cat]


SFX_PEAK = 0.85            # tetto di picco degli effetti (circa -1,4 dBFS: margine per l'OGG)


def to_pcm(x):
    return (np.clip(x, -1.0, 1.0) * 32767).astype("<i2")


def write_wav(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if x.ndim == 1 else x.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(to_pcm(x).tobytes())


def have_ogg():
    return shutil.which("ffmpeg") is not None


def write_ogg(path, x, quality):
    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "t.wav")
        write_wav(tmp, x)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-map_metadata", "-1",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact", "-c:a", "libvorbis",
                        "-q:a", str(quality), "-serial_offset", "1", path], check=True)


def edge_fade(x, a=0.003, r=0.02):
    """Dissolvenza minima su inizio e fine di un effetto (mono o stereo): garantisce campioni ~0 ai bordi."""
    x = x.copy()
    na, nr = min(len(x), int(a * SR)), min(len(x), int(r * SR))
    ga, gr = np.linspace(0, 1, na), np.linspace(1, 0, nr)
    if x.ndim == 2:
        ga, gr = ga[:, None], gr[:, None]
    x[:na] *= ga
    x[-nr:] *= gr
    return x


def limit_peak(x, peak=SFX_PEAK):
    m = float(np.max(np.abs(x)))
    return x * (peak / m) if m > peak else x


# ------------------------------------------------------------------ misure (--report / --check)
LIMITS = {
    "peak_db_max": -1.0,           # picco massimo dopo la codifica (dBFS)
    "music_lufs_spread_max": 3.0,  # differenza massima di loudness stimata fra tracce (dB)
    "music_dur": (24.0, 48.0),
    "music_centroid_max": 2200.0,  # Hz: spettro non stridulo
    "music_hf6k_max": 0.01,        # quota di energia sopra 6 kHz
    "music_hf4k_max": 0.05,        # quota di energia sopra 4 kHz
    "seam_ratio_max": 3.0,         # salto fra ultimo e primo campione / 99° percentile delle differenze
    "edge_silence_max_s": 0.25,    # silenzio (< -60 dBFS) a inizio/fine traccia
    "inner_silence_max_s": 1.0,    # finestre di 1 s con RMS < -55 dBFS dentro la traccia
    "total_mb_max": 12.0,
    "dc_max": 0.003,               # offset in continua (frazione del fondo scala): sotto -50 dBFS
    "sfx_edge_max": 0.03,          # |campione| al primo/ultimo istante di un effetto (fade: niente click)
    "sfx_lufs_tol": 2.5,           # scarto massimo dal riferimento di categoria (picco limitato -> puo' scendere)
}


def decode(path):
    """Decodifica un file audio con ffmpeg (o legge il WAV). Ritorna array float (n,) o (n,2)."""
    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "d.wav")
        if path.endswith(".wav"):
            tmp = path
        else:
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "pcm_s16le", tmp], check=True)
        with wave.open(tmp, "rb") as w:
            ch, n = w.getnchannels(), w.getnframes()
            raw = np.frombuffer(w.readframes(n), dtype="<i2").astype(float) / 32768.0
    return raw.reshape(-1, ch) if ch > 1 else raw


def analyze(x, music):
    m = x.mean(axis=1) if x.ndim == 2 else x
    xs0 = x if x.ndim == 2 else x[:, None]
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x ** 2)))
    out = {"dur": len(x) / SR, "ch": 1 if x.ndim == 1 else x.shape[1], "peak_db": 20 * np.log10(max(peak, 1e-9)),
           "rms_db": 20 * np.log10(max(rms, 1e-9)), "lufs": loudness(x), "clip": int(np.sum(np.abs(x) >= 0.999))}
    out["dc"] = float(abs(np.mean(m)))
    out["edge"] = float(max(np.max(np.abs(xs0[0])), np.max(np.abs(xs0[-1]))))
    spec = np.abs(np.fft.rfft(m)) ** 2
    fr = np.fft.rfftfreq(len(m), 1.0 / SR)
    tot = max(float(spec.sum()), 1e-12)
    out["centroid"] = float((spec * fr).sum() / tot)
    out["hf4k"] = float(spec[fr > 4000].sum() / tot)
    out["hf6k"] = float(spec[fr > 6000].sum() / tot)
    xs = x if x.ndim == 2 else x[:, None]
    d = np.abs(np.diff(xs, axis=0))
    p99 = float(np.percentile(d, 99)) + 1e-9
    out["seam_ratio"] = float(np.max(np.abs(xs[0] - xs[-1])) / p99)
    thr = 10 ** (-60 / 20)
    nz = np.where(np.abs(m) > thr)[0]
    out["lead_sil"] = float(nz[0] / SR) if len(nz) else out["dur"]
    out["tail_sil"] = float((len(m) - 1 - nz[-1]) / SR) if len(nz) else out["dur"]
    w = SR                                                          # finestre di 1 s
    worst = 1.0
    if music and len(m) >= w:
        worst = min(float(np.sqrt(np.mean(m[i:i + w] ** 2))) for i in range(0, len(m) - w + 1, w // 2))
    out["min_win_rms_db"] = 20 * np.log10(max(worst, 1e-9))
    return out


def audio_files(base):
    res = []
    for sub in ("sfx", "music"):
        d = os.path.join(base, sub)
        if os.path.isdir(d):
            for f in sorted(os.listdir(d)):
                if f.endswith((".ogg", ".wav")):
                    res.append((sub, f, os.path.join(d, f)))
    return res


def measure_all(base):
    rows = []
    for sub, f, p in audio_files(base):
        a = analyze(decode(p), sub == "music")
        a.update(kind=sub, file=f, kb=os.path.getsize(p) / 1024.0)
        rows.append(a)
    return rows


def check_rows(rows):
    """Ritorna la lista dei problemi (vuota = tutto bene)."""
    L, bad = LIMITS, []
    for a in rows:
        n = a["file"]
        if a["clip"]:
            bad.append("%s: clipping (%d campioni)" % (n, a["clip"]))
        if a["peak_db"] > L["peak_db_max"]:
            bad.append("%s: picco %.2f dBFS > %.1f" % (n, a["peak_db"], L["peak_db_max"]))
        if a["dc"] > L["dc_max"]:
            bad.append("%s: offset DC %.4f" % (n, a["dc"]))
        if a["kind"] == "sfx":
            if a["edge"] > L["sfx_edge_max"]:
                bad.append("%s: click a inizio/fine (campione %.3f)" % (n, a["edge"]))
            tgt = sfx_target(n.rsplit(".", 1)[0])
            if abs(a["lufs"] - tgt) > L["sfx_lufs_tol"]:
                bad.append("%s: loudness %.1f LUFS~ lontana dal riferimento %.1f" % (n, a["lufs"], tgt))
        if a["kind"] == "music":
            if not L["music_dur"][0] <= a["dur"] <= L["music_dur"][1]:
                bad.append("%s: durata %.1f s fuori %s" % (n, a["dur"], L["music_dur"]))
            if a["centroid"] > L["music_centroid_max"]:
                bad.append("%s: centroide %.0f Hz troppo alto" % (n, a["centroid"]))
            if a["hf6k"] > L["music_hf6k_max"] or a["hf4k"] > L["music_hf4k_max"]:
                bad.append("%s: troppa energia acuta (>4k %.1f%%, >6k %.1f%%)" % (n, a["hf4k"] * 100, a["hf6k"] * 100))
            if a["seam_ratio"] > L["seam_ratio_max"]:
                bad.append("%s: click al punto di loop (rapporto %.1f)" % (n, a["seam_ratio"]))
            if a["lead_sil"] > L["edge_silence_max_s"] or a["tail_sil"] > L["edge_silence_max_s"]:
                bad.append("%s: silenzio a inizio/fine" % n)
            if a["min_win_rms_db"] < -55.0:
                bad.append("%s: buco di silenzio interno (%.1f dB)" % (n, a["min_win_rms_db"]))
        elif a["dur"] < 0.03:
            bad.append("%s: troppo breve" % n)
    mus = [a["lufs"] for a in rows if a["kind"] == "music"]
    if mus and max(mus) - min(mus) > L["music_lufs_spread_max"]:
        bad.append("musica: scarto di loudness %.2f dB > %.1f" % (max(mus) - min(mus), L["music_lufs_spread_max"]))
    tot = sum(a["kb"] for a in rows) / 1024.0
    if tot > L["total_mb_max"]:
        bad.append("peso totale %.2f MB > %.0f MB" % (tot, L["total_mb_max"]))
    return bad


def print_report(rows):
    print("%-26s %6s %2s %7s %7s %7s %6s %5s %5s %6s %7s" % ("file", "dur", "ch", "peak", "rms", "LUFS~", "centr", ">4k%", "seam", "KB", "silTail"))
    for a in rows:
        print("%-26s %6.1f %2d %7.1f %7.1f %7.1f %6.0f %5.1f %5.1f %6.0f %7.2f" % (
            a["file"], a["dur"], a["ch"], a["peak_db"], a["rms_db"], a["lufs"], a["centroid"], a["hf4k"] * 100,
            a["seam_ratio"], a["kb"], a["tail_sil"]))
    mus = [a for a in rows if a["kind"] == "music"]
    if mus:
        l = [a["lufs"] for a in mus]
        print("MUSICA: %d tracce, LUFS stimata min %.2f max %.2f (scarto %.2f dB), durata %.1f-%.1f s, %.2f MB" % (
            len(mus), min(l), max(l), max(l) - min(l), min(a["dur"] for a in mus), max(a["dur"] for a in mus),
            sum(a["kb"] for a in mus) / 1024))
    sf = [a for a in rows if a["kind"] == "sfx"]
    if sf:
        print("EFFETTI: %d file, picco max %.2f dBFS, %.2f MB" % (len(sf), max(a["peak_db"] for a in sf), sum(a["kb"] for a in sf) / 1024))
    print("TOTALE: %.2f MB" % (sum(a["kb"] for a in rows) / 1024))

# ------------------------------------------------------------------ manifest (assets_plan/audio_manifest.csv)
MUSIC_DESC = {
    "menu": "Vaelmora e menù: liuto arpeggiato, flauto e pad morbido",
    "skilling": "Mansioni: arpa, pizzicati e pad sereno, produttività tranquilla",
    "combat_early": "Combattimento zone 1-4: avventuroso leggero, tamburi morbidi, archi",
    "combat_mid": "Combattimento zone 5-7: più cupo, archi bassi, percussioni",
    "combat_late": "Combattimento zone 8-10: epico e celeste, coro senza parole, campane",
    "dungeon": "Dungeon: tensione bassa, droni, campanelli lontani",
    "boss": "Boss mondiali e Incursioni: ritmico, ottoni dolci, crescendo controllato",
    "rift": "La Breccia: pad scalare a toni interi, scintille di vetro, battito profondo",
    "estate": "Tenuta: campagna serena, chitarra e fisarmonica leggera",
    "prestige": "Prestigio ed Ere: cori lenti, arpeggi aperti, campane",
    "vault": "Sala dei Caveau e Rullo: celesta e vibrafono, misterioso e scintillante",
    "event": "Eventi (fiere, mercato): festoso e leggero, pizzicati e flauto",
}
SKILL_DESC = {
    "woodcutting": "colpo d'ascia su tronco", "mining": "piccone su roccia con eco", "fishing": "lenza lanciata e splash",
    "foraging": "falcetto che taglia l'erba", "trapping": "scatto di trappola di legno",
    "smithing": "martello su incudine", "woodworking": "sega a mano", "tailoring": "forbici su stoffa",
    "cooking": "sfrigolio in padella", "alchemy": "bollicine e vetro", "jewelcrafting": "scalpello su gemma",
    "runecarving": "incisione di una runa", "keysmithing": "lima su chiave", "thievery": "monete e mantello",
    "farming": "zappa nel terreno", "hero": "fendente di spada", "bounty": "timbro sul manifesto",
}
SFX_DESC = {
    "ui_click": "clic di interfaccia", "ui_confirm": "conferma", "ui_error": "errore", "ui_notify": "notifica",
    "ui_achievement": "impresa sbloccata (stinger)", "ui_pet": "famiglio trovato", "ui_star": "stella ottenuta",
    "ui_welcome": "jingle del Bentornato (offline)", "ui_unlock": "funzione sbloccata", "action_done": "azione/spedizione completata",
    "level_up": "level up (stinger)", "quest_done": "missione completata (stinger)", "crate_open": "apertura della Cassa",
    "reel_tick": "tick del rullo (volume/tono dal segnale)", "reveal_rare": "rivelazione Rara (accordo semplice)",
    "reveal_epic": "rivelazione Epica", "reveal_legendary": "rivelazione Leggendaria", "reveal_mythic": "rivelazione Mitica",
    "reveal_relic": "rivelazione ★ Reliquia (fanfara breve)", "hit": "colpo dell'eroe", "victory": "vittoria (stinger)",
    "defeat": "sconfitta di una prova (stinger morbido)", "death": "morte dell'eroe", "prestige": "rito/prestigio (stinger ampio)",
    "era": "nuova Era (stinger)", "coin": "moneta", "sell": "vendita",
    "hit_crit": "colpo critico", "dodge": "schivata", "hurt": "colpo subito dall'eroe", "kill": "mostro sconfitto",
    "buy": "acquisto", "crate_found": "Cassa trovata", "drop_rare": "oggetto raro ottenuto", "coop_link": "co-op: amico collegato",
}


def write_manifest():
    """Riscrive assets_plan/audio_manifest.csv dai file prodotti (id = nome file; contesto per la musica)."""
    path = os.path.join(ROOT, "assets_plan", "audio_manifest.csv")
    rows = [["id", "categoria", "descrizione_prompt", "durata", "milestone", "cartella", "contesto"]]
    for sp in MUSIC_SPECS:
        dur = sp["bars"] * 4 * 60.0 / sp["bpm"]
        rows.append([sp["name"], "music", "%s (%d bpm, %s, loop %.0f s, variante %s)" % (
            MUSIC_DESC[sp["ctx"]], sp["bpm"], sp["mode"], dur, sp["name"].rsplit("_", 1)[1]),
            "%.0f s" % dur, "AUDIO-2", "audio/music", sp["ctx"]])
    for k in SFX:
        if k.startswith("sk_"):
            sk, v = k[3:].rsplit("_", 1)
            rows.append([k, "sfx_skill", "%s (variante %s), morbido, volume basso" % (SKILL_DESC[sk], v), "0.5-0.8 s",
                         "AUDIO-2", "audio/sfx", "mansione:" + sk])
        else:
            cat = "sfx_ui" if k.startswith(("ui_", "action", "level", "quest", "coin", "sell", "buy", "prestige", "era", "coop", "drop")) else (
                "sfx_crate" if k.startswith(("crate", "reel", "reveal")) else "sfx_combat")
            rows.append([k, cat, SFX_DESC.get(k, k), "0.1-5 s", "AUDIO-2", "audio/sfx", ""])
    with open(path, "w", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wav", action="store_true", help="forza WAV 22 kHz")
    ap.add_argument("--only", help="genera solo questo nome")
    ap.add_argument("--out", default=os.path.join(ROOT, "game", "assets", "audio"))
    ap.add_argument("--report", action="store_true", help="misura i file già generati (picco, RMS, loudness, loop...)")
    ap.add_argument("--check", action="store_true", help="come --report, ma esce con 1 se un limite è violato")
    ap.add_argument("--no-gen", action="store_true", help="con --report/--check: non rigenerare")
    a = ap.parse_args()
    if (a.report or a.check) and a.no_gen:
        rows = measure_all(a.out)
        print_report(rows)
        bad = check_rows(rows)
        for b in bad:
            print("PROBLEMA:", b)
        return 1 if (a.check and bad) else 0
    ogg = have_ogg() and not a.wav
    ext = ".ogg" if ogg else ".wav"
    total = 0
    jobs = [("sfx", k, (lambda f=f, k=k: f(rng_for(k))), 3) for k, f in SFX.items()]
    jobs += [("music", k, f, 3) for k, f in MUSIC.items()]
    wanted = {}
    for sub, name, make, q in jobs:
        wanted.setdefault(sub, set()).add(name + ext)
        if a.only and a.only != name:
            continue
        d = os.path.join(a.out, sub)
        os.makedirs(d, exist_ok=True)
        for old in (".ogg", ".wav"):                       # niente doppioni dello stesso suono
            if old != ext and os.path.exists(os.path.join(d, name + old)):
                os.remove(os.path.join(d, name + old))
        p = os.path.join(d, name + ext)
        x = make()
        if sub == "sfx":
            x = edge_fade(x)                                # niente click a inizio/fine (3 ms in, 20 ms out)
            if name.startswith("sk_"):                      # mansioni: stessa loudness (-25,5 LUFS stimati), spettro morbido
                x = circ_filter(x, None, 6500.0, 2)
                x = x * 10.0 ** ((SKILL_LUFS - loudness(x)) / 20.0)
                x = limit_peak(x, 0.62)
            else:                                           # stessa loudness per categoria (vedi SFX_TARGET_LUFS)
                x = x * 10.0 ** ((sfx_target(name) - loudness(x)) / 20.0)
            x = limit_peak(x)
        if ogg:
            write_ogg(p, x, q)
        else:
            write_wav(p, x)
        total += os.path.getsize(p)
        print(f"{sub}/{name}{ext}  {len(x) / SR:5.1f} s  {os.path.getsize(p) / 1024:6.1f} KB")
    if not a.only:                                         # rimuove i file non più prodotti (e i loro .import)
        for sub, names in wanted.items():
            d = os.path.join(a.out, sub)
            for f in os.listdir(d):
                base = f[:-7] if f.endswith(".import") else f
                if base.endswith((".ogg", ".wav")) and base not in names:
                    os.remove(os.path.join(d, f))
                    print("rimosso", sub + "/" + f)
        write_manifest()
    print(f"TOTALE {total / 1024:.0f} KB ({'OGG Vorbis' if ogg else 'WAV'})")
    if a.report or a.check:
        rows = measure_all(a.out)
        print_report(rows)
        bad = check_rows(rows)
        for b in bad:
            print("PROBLEMA:", b)
        return 1 if (a.check and bad) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
