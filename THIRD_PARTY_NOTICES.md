# Third-party notices

Pumpkin has no third-party Swift package dependencies. It uses macOS system frameworks.

The launch media uses **Fredoka** and **DM Sans**, distributed under the SIL Open Font License 1.1. The font files and their full licenses are in `media/launch/fonts/`.

The Pumpkin launch illustration was generated with OpenAI ImageGen for this project. The generation prompt is in `media/launch/ART_DIRECTION.md`. It is included under this repository's MIT license.

The application icon and menu bar glyph are original, reproducible vector drawings in `scripts/make_icon.swift` and `StatusItemController.swift`. UI screenshots are rendered from Pumpkin using synthetic demo files. The announcement video's sounds are procedural accents, not third-party recordings.

Tesseract 0.3.0 was used locally to author/render the editable launch composition. Its executable and dependencies are not distributed in this repository. The `.tsrct` document contains the OFL fonts and project artwork listed above.

## Able Recorder recording engine

`Sources/PumpkinAudioBridge` and `Sources/PumpkinApp/Recording/{Capture,Devices,SelfTest}.swift` adapt the native recording engine from [Able Recorder](https://github.com/baogli/able-recorder/tree/099938c97b47b28abfd0e48a0b1010101b7a3bc0). The complete upstream license follows. Pumpkin's clipboard module is independently implemented from the product requirements; no unlicensed Vee source was copied.

```text
MIT License

Copyright (c) 2026 Able Recorder contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
