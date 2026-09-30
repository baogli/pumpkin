# Pumpkin launch kit

- `Pumpkin-launch.mp4`: 21 seconds, 1600 × 900, 30 fps, H.264 + AAC, suitable for attaching to a GitHub release or a Twitter/X announcement.
- `Pumpkin.tsrct`: portable editable Tesseract 0.3.0 composition with native text, file cards, groups, animation, three separate synthesized sound cues, UI images and OFL fonts.
- `Previews/Filmstrip.png`: final eight-frame storyboard.
- `../../docs/pumpkin-banner.png`: announcement/README cover.
- `../../docs/pumpkin-illustration.png`: original generated illustration.
- `ANNOUNCEMENTS.md`: English and Russian Twitter/X copy and GitHub repository description. The repository links are ready to publish.
- `ART_DIRECTION.md`: ImageGen prompt and motion decisions.
- `fonts/`: Fredoka and DM Sans with SIL Open Font License 1.1 notices.

The screenshots are actual Pumpkin UI rendered with synthetic test files. The demonstration abbreviates timer waits and labels them as accelerated. It is an explainer, not a real-time screen recording.

To revise the portable composition with Tesseract 0.3.0, check it out, use supported native actions, and export it. For rebuilding the authored layer tree, `author.py` reads `.tesseract-work/editable.json` and writes the media-layer document plus an action batch:

```bash
mkdir -p .tesseract-work
tsrct project checkout --project Pumpkin.tsrct --output .tesseract-work/editable.json
python3 author.py
tsrct project commit --project Pumpkin.tsrct --file .tesseract-work/editable.json
tsrct project apply --project Pumpkin.tsrct --actions .tesseract-work/edits.json
tsrct export --project Pumpkin.tsrct --fps 30 --output Pumpkin-launch.mp4
```

These commands rebuild the branded composition, replacing its authored layer tree; keep a checkpoint before your own custom revisions. The original code-driven artwork and UI panels can be regenerated from the app source and QA tool.

Review: native document validation passed; the final filmstrip and full-size poster were visually inspected; the exported video and complete AAC audio stream were decoded using macOS AVFoundation. The audio is a sparse set of soft accents, not narration or a music bed. Final creative review belongs to the person announcing the app.
