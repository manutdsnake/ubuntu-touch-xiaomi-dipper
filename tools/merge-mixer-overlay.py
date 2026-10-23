#!/usr/bin/env python3
"""Merge the vendor's mixer_paths_overlay_static.xml into mixer_paths_tavil.xml.

LineageOS' 32-bit audio HAL applies the static overlay itself (the dipper
analog mics, the TAS2557 on QUAT_MI2S, ...); the 64-bit HAL that PulseAudio
loads was built without overlay support and used the generic SDM845 paths -
DMICs the Mi 8 does not have, so every recording was silence.  The overlay's
own rules: its top-level ctls override the defaults, each first-level path
replaces the path of the same name (or is added).

Only the capture side and the earpiece paths are taken over (paths and defaults that touch ADC/AMIC/
DMIC/TX/DEC controls and no RX control): taking the whole overlay also moved
the speaker onto the overlay's QUAT_MI2S setup (mono S24, TAS2557
"Configuration" 10), which the 64-bit HAL does not configure the backend for -
the speaker went silent.

Usage: merge-mixer-overlay.py base.xml overlay_static.xml out.xml
"""
import sys
import xml.etree.ElementTree as ET

base = ET.parse(sys.argv[1]); b = base.getroot()
o = ET.parse(sys.argv[2]).getroot()
top = {c.get('name'): c for c in b.findall('ctl')}
paths = {p.get('name'): p for p in b.findall('path')}
nc = npth = 0
import re
TX = re.compile(r'ADC|AMIC|DMIC|TX|DEC|IIR')
RX = re.compile(r'RX|Spkr|SPK|EAR|HPH|Configuration|INT\d')
EAR = re.compile(r'EAR|RX INT0')
NOT_EAR = re.compile(r'Configuration|QUAT|SpkrLeft|SpkrRight|WSA')
def capture_only(el):
    names = [el.get('name')] if el.tag == 'ctl' else [c.get('name') for c in el.iter('ctl')]
    capture = any(TX.search(n) for n in names) and not any(RX.search(n) for n in names)
    # The earpiece too: the base "handset" path is the SDM845 reference's WSA
    # speaker; the Mi 8's earpiece is the codec EAR output on RX INT0, which
    # only the overlay has (no sound from the earpiece in calls without it).
    earpiece = el.tag == 'path' and any(EAR.search(n) for n in names) \
        and not any(NOT_EAR.search(n) for n in names)
    return capture or earpiece
for el in o:
    if not capture_only(el):
        continue
    if el.tag == 'ctl':
        n = el.get('name')
        if n in top:
            top[n].set('value', el.get('value'))
        else:
            # keep defaults before the first path, as audio_route expects
            idx = list(b).index(b.find('path'))
            b.insert(idx, el); top[n] = el
        nc += 1
    elif el.tag == 'path':
        n = el.get('name')
        # The base defines some paths more than once; replace every copy.
        same = [p for p in b.findall('path') if p.get('name') == n]
        if same:
            i = list(b).index(same[0])
            for p in same:
                b.remove(p)
            b.insert(i, el)
        else:
            b.append(el)
        paths[n] = el; npth += 1
# Port additions (tools/mixer-port-additions.xml): controls appended to paths.
import os
add = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mixer-port-additions.xml')
if os.path.exists(add):
    ar = ET.parse(add).getroot()
    for c in ar.findall('ctl'):
        n = c.get('name')
        if n in top:
            top[n].set('value', c.get('value'))
        else:
            b.insert(list(b).index(b.find('path')), c); top[n] = c
    for ap in ar.findall('path'):
        for p in b.findall('path'):
            if p.get('name') == ap.get('name'):
                for c in ap.findall('ctl'):
                    p.append(c)
base.write(sys.argv[3], encoding='ISO-8859-1', xml_declaration=True)
print(f'{nc} default ctls, {npth} paths from the overlay', file=sys.stderr)
