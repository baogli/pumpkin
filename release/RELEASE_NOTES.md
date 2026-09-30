# Pumpkin 1.0.0 🎃

![Pumpkin](https://raw.githubusercontent.com/baogli/pumpkin/v1.0.0/docs/pumpkin-banner.png)

Every file gets its midnight.

Pumpkin gives downloads and screenshots an expiry time, then moves them to the Trash automatically. It lives in the macOS menu bar and keeps everything on your Mac.

- Pick 10 minutes, 30 minutes, an hour, a day, a week, or 30 days — or Keep Forever.
- Watch downloads and real macOS screenshots, with previews and grouped prompts.
- See expiring files, change timers, pause the countdown, or Put Back an item from the Trash.
- Use the new pumpkin icon, menu bar glyph, and Pumpkin branding throughout.
- Import timers and preferences from the earlier local ShelfLife build without overwriting existing Pumpkin settings.
- Keep panels usable even if AppKit suspends their window animations.

**Download:** `Pumpkin-1.0.0-macOS.zip` — universal Apple Silicon + Intel, macOS 14+.

Unzip, drag Pumpkin into Applications, and open it. This community build is ad-hoc signed and **not Apple notarized**; macOS may require you to review and approve its first launch using [Apple’s instructions](https://support.apple.com/en-ie/102445). Source is included under MIT for building or auditing yourself.

Quit the older ShelfLife app before upgrading. You may need to grant folder permissions again and update its login-item setting.

**Validation:** 60 tests and 80 local end-to-end/UI checks passed on macOS 26.5.2 / Xcode 26.6. The bundled executable contains `arm64` and `x86_64` architectures and passes strict signature verification. Checksums are supplied in `SHA256SUMS`.

**Launch kit:** 21-second H.264/AAC announcement video, artwork, actual UI screenshots, and a portable editable Tesseract composition. The video's demo timers are accelerated.

[Watch the 21-second announcement video](https://github.com/baogli/pumpkin/releases/download/v1.0.0/Pumpkin-launch.mp4) · [Twitter/X announcement copy](https://github.com/baogli/pumpkin/blob/v1.0.0/media/launch/ANNOUNCEMENTS.md)

The portable `Pumpkin.tsrct` source is attached for editing the announcement. Hosted CI has not run; this release uses the completed local validation described above.
