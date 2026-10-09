#!/usr/bin/env python3
"""Fictional all-EXIF orientation/source-coordinate smoke check, no app install."""
import argparse
import collections
import json
from pathlib import Path
import sys
import compare as c

def run(folder, report):
    summaries = {}
    for mode in ('baseline', 'document-lines'):
        reference = None
        for raw in range(1,9):
            image = folder/f'orientation-{raw}.jpg'
            digest = c.a.e.input_digest(image)
            response = c.a.capture_worker(Path('/tmp/Sliplet-P2-02-worker'), dict(image=str(image),mode=mode))
            c.verify_membership(response)
            if response['orientation'] != raw or digest != c.a.e.input_digest(image): raise ValueError('orientation_or_original_changed')
            observations = response['observations']
            by_text = {o['text']:o['boundingBox'] for o in observations}
            if len(by_text) != len(observations): raise ValueError('ambiguous_synthetic_text')
            # At least top and bottom survive; matching every returned transcription
            # and normalized box checks full oriented source space, including mirrors.
            if not any('COSTCO' in t for t in by_text) or not any('TOTAL' in t for t in by_text): raise ValueError('long_image_trimmed')
            if reference is None: reference = by_text
            if set(reference) != set(by_text): raise ValueError('orientation_transcription_difference')
            for text, box in by_text.items():
                if any(abs(box[k]-reference[text][k]) > .015 for k in ('x','y','width','height')): raise ValueError('orientation_coordinate_difference')
        summaries[mode] = dict(orientations_passed=8, normalized_box_tolerance=.015, first_last_text_present=True, original_jpegs_unchanged=True,
                               mixed_language_recognized=any('茶' in t for t in reference) and any('米' in t for t in reference), observations=len(reference))
    report.write_text(json.dumps(dict(fictional=True, variants=summaries), indent=2)+'\n')
    print('passed: 16 fictional orientation requests, full-page ends, stable oriented coordinates and original bytes')

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--folder', type=Path, required=True); parser.add_argument('--report', type=Path, required=True)
    args=parser.parse_args()
    try: run(args.folder,args.report)
    except Exception: print('orientation_failed; diagnostics suppressed'); sys.exit(1)
