# Review fixes — 2.0.0 preview 2 / build 3

Reviewed and verified locally on 2026-10-01. This preview fixes the reported duplicate clipboard and defects found in the clipboard, recorder interface and cleanup workflow.

| Problem | Result |
| --- | --- |
| Quick Clipboard could overlap the main Clipboard workspace | Opening either dismisses the other. Automatic cleanup panels remain deferred throughout the transition. |
| A late main-window key event could mark an already hidden window visible | Visibility callbacks read the actual window state; hiding the workspace stays authoritative. |
| Shared global registration let Pumpkin and a previous clipboard app respond together | Shortcuts register exclusively. Actual conflicts are reported; failed registrations retry when another app exits. Old apps are not automatically quit or modified. |
| Both modules could be assigned the same shortcut | Neither ambiguous binding is registered; settings explain how to choose distinct combinations. |
| New history items changed the meaning of a selected index | Each quick popup keeps a stable snapshot until dismissed. A new copy cannot silently replace the highlighted text. |
| An old confirmation timer could dismiss a newer clipboard popup | Dismissals and asynchronous paste failures are tied to their own presentation. |
| Disabled or cleared clipboard retained a visible popup | The popup closes and its snapshot clears with the RAM history. |
| Paste cancellation left callbacks unresolved | Focus changes, newer copies and disable/clear cancel once, restore only an owned temporary pasteboard, and preserve newer user content. Automatic insertion requires an enabled, writable text control. |
| Importing one MP4 discarded its entire pending download group | Only the imported file is removed. Other questions persist across restart. |
| Pending renames/deletions were not immediately saved | Every changed question persists immediately, with folder-scoped updates and volume/inode identity. |
| Switching the download folder discarded pending screenshot questions | Outstanding questions survive; separate folders do not merge or erase each other's questions. Clicking the current duration also persists the interaction. |
| Answering a question during pause created excess remaining time | New timers use the frozen clock, then resume with the chosen duration. |
| Screenshot-only watching stopped when its folder equaled the disabled Downloads folder | The screenshot watcher remains independent; screenshot folder access is checked even with Downloads off. |
| Cleanup filters mixed unrelated history and relied on screenshot-like filenames | Counts, questions, timers and Trash history use the selected category. Origin is saved for new entries and survives renaming and Trash; legacy files use actual metadata. |
| Renamed recordings in Trash could receive another timer | Recording/Trash association follows file identity. No timer can target a Trash path; Put Back verifies identity before restoring new records. |
| Failed recordings protected unrelated replacements at the same path | Path protection applies while capture is pending; completed/failed files use identity. All partial MP4 files remain excluded from automatic expiry. |
| Starting recording after the audio check required a hotkey | The visible Start Recording button remains available during monitoring. |
| Appearance changes left native controls in the previous theme; error notices looked successful | Native window appearance changes immediately. Failure notices show an error symbol and color. |
| Models and clipboard controllers left observer/monitor/timer registrations behind | Registrations are removed when owners are released. Clip count is bounded in memory as well as preferences; recording duration is finite before saving. |

Regression coverage is in `Tests/PumpkinAppTests/ReviewRegressionTests.swift` and `Sources/PumpkinV2QA/main.swift`. Tests use private pasteboards, temporary files and controlled callback injection. The cross-process hotkey fixture starts with a shared binding and verifies exclusive ownership against another process, then recovery after it exits. It does not send clipboard text to another app.

The native file-panel QA and unified-window QA must run sequentially: simultaneous GUI harnesses can compete for WindowServer focus. The unified harness disables outside-click/workspace monitors for its private test controllers; real user clicks must not silently change the scenario under test. Local AppKit event routing remains active, and production controllers retain their outside monitors. Synthetic media results from preview 1 remain applicable to the unchanged capture/writer pipeline. Physical loopback, external-app automatic insertion and the remaining acceptance matrix are still tracked in [TESTING.md](TESTING.md); this review does not mark those hardware scenarios complete.
