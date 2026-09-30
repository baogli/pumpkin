# Contributing to Pumpkin

Bug reports and small focused pull requests are welcome. Include your macOS version, the steps to reproduce, and what you expected. Avoid sharing screenshots or logs containing personal file names unless you have reviewed them.

Use Xcode 26 or later. Run `swift test` before submitting. For changes to panels, onboarding, or interactions, also run `swift run PumpkinQA qa-output` in a local graphical macOS session and inspect the generated light/dark snapshots.

Preserve the core file-safety rules: Trash rather than permanent deletion, inode identity checks, watched-folder boundaries, unfinished-download filtering, safe defaults for unanswered prompts, and reversible upgrades. Add a focused regression test when changing one of these behaviors.

The build and release scripts are `scripts/build.sh` and `scripts/package-release.sh`. Generated build caches, local state, and private signing credentials do not belong in source control.

Contributions are made under the MIT license.
