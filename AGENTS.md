# moiraine-ios

moiraine on iPhone: a native SwiftUI client of gaidin's HTTP API (`../gaidin`, `src/web.ts`'s `Gets`, `Posts` and `StreamEvent`), following moiraine's design system. This repository is public.

## Commands

- `cd MoiraineCore && swift test` and `sh scripts/e2e.sh` before every commit. The UI tests start gaidin's faux server from `../gaidin`, which needs `pnpm install` run there.
- `xcodegen generate` after changing `project.yml` or adding files; never edit `Moiraine.xcodeproj`.

## Where things are

- The README's Layout section says where each part lives.
- Look and feel follow moiraine's `design.md` and `tokens.css` (github.com/brad-j/moiraine). `App/Theme.swift` holds the tokens as they're written there; change them in moiraine first if both apps should move together. Where this app differs from moiraine (the phone's frame, what isn't built yet), say so in the README.
- `MoiraineCore` mirrors moiraine's code: `Transcript.swift` is `src/transcript.ts`, `LogLines.swift` is `src/conversation/log.tsx`, `Format.swift` is `src/format.ts`. A change to how gaidin's events are read is made in both.

## Rules

- The app is a client only. A change it needs from gaidin is made in gaidin, in its own commit there.
- `PROTOCOL` in `API.swift` is gaidin's protocol version this build is written against. When gaidin raises it, check what changed in `src/web.ts` and raise it here with the change.
- Decoding stays lenient: an event, block or field this build doesn't know is skipped, never a failure that drops the stream.
- The safety code is `Client.swift` and `EventStream.swift` (the boundary with gaidin) and `MarkdownView.swift` (model output, which renders as views and opens only http and https links). A change that lets through anything these used to stop says so in its commit message and has a test.
- A UI change comes with a UI test that shows it working.
- Don't add a package without asking.
- Nothing about the owner's own setup goes in code, tests or docs: no real names, host names, tailnet addresses, team IDs or device IDs. The tests' user is `brad@example.com`; use `example.com` and `*.test` names.
- Commit messages describe the change in a sentence or more of prose, with no `feat:`-style prefixes.
