# Pumpkin art and motion

The visual idea is a friendly pumpkin helping temporary files find their midnight.
Orange clay, warm cream, and forest green keep the utility playful and readable.

## Illustration

### ImageGen prompt

> Use case: ads-marketing. Asset type: launch illustration for Pumpkin, an open-source macOS menu bar utility that gives downloads and screenshots an expiry timer and then moves them to Trash. Create a sophisticated playful 3D clay-style illustration, wide landscape composition. A friendly round orange pumpkin mascot with small bright eyes and a mischievous smile, a tiny green stem, gently sweeping a few floating paper document icons and screenshot cards toward a small clean recycling bin. A little clock near the pumpkin suggests file expiry. Rich warm orange, cream and deep forest-green palette, warm cream background, soft studio light, tactile ceramic/clay texture, rounded forms, clean premium indie Mac app feeling. Pumpkin sits in the right half, leave ample beautifully balanced negative space on the left for a title we add later in code. No lettering, no watermarks, no Apple logos, no scary Halloween face, no ghosts, no actual screenshot or invented UI. The pumpkin is adorable, useful and funny rather than spooky.

Generated with the built-in OpenAI ImageGen tool. The original image is
`../../docs/pumpkin-illustration.png`; the title, slogan, and application icon on
the banner are native editable layers in `Pumpkin.tsrct`.

The illustration is promotional artwork. It does not represent the actual UI.
The program's icon and menu bar glyph are reproducible drawings in Swift.

## Motion

- 0–3 seconds: floating temporary-file cards and the opening joke.
- 3–6 seconds: the pumpkin arrives and introduces the app.
- 6–10.5 seconds: actual download and screenshot timer panels.
- 10.5–13.5 seconds: the real move-to-Trash notice.
- 13.5–16.5 seconds: the real restoration notice.
- 16.5–21 seconds: the name, midnight slogan, and availability.

Demo waits are abbreviated and explicitly labelled. Native typography, grouped
file cards, opacity/position keyframes, small rotations, and three separately
editable synthesized accents carry the animation. Fonts are Fredoka and DM Sans,
both under SIL OFL 1.1 with license files in `fonts/`.

## Review

The final full-size banner and eight-frame storyboard were visually inspected.
AVFoundation measured a 21-second, 1600 × 900, 30 fps H.264 video and decoded its
complete AAC track. The sparse sound accents peak around -15.6 dBFS; this is a
sample-peak measurement, not a true-peak or LUFS claim. The completed composition
and MP4 are supplied for final playback and creative review.
