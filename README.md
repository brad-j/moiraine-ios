# moiraine-ios

moiraine on iPhone: a native SwiftUI client for [gaidin](https://github.com/brad-j/gaidin), beside [moiraine](https://github.com/brad-j/moiraine)'s web app. It talks to gaidin's HTTP API over the tailnet, as the web app does, and follows moiraine's design system (`design.md` there).

## What it does

- The rail of agents, each with a pulsing dot while it works and an amber count of what waits on you, and each agent's column: Home, + thread, and its threads, job runs and conversations from other agents, by day.
- A conversation as moiraine draws it: the log's gutter beside a hairline, answers in Markdown revealed a word at a time, tool calls and thinking folded to a line, steps in a row gathered, fired reminders with snooze, and job reports.
- The dock: every agent's requests, with Allow once, the wider grant and Deny for a call, and a question's choices as buttons. A message typed while a question waits is taken as the answer, as gaidin does.
- The composer: a field across the screen with Send, or Stop while a run goes, on a row of its own, and the status line under it (working or reconnecting, the model, and the day's spend against its limit). What's typed and not sent is kept for each conversation.
- New threads, and a message to a job run or another agent's conversation forks it and moves to the fork.

Not yet: the pages (Schedule, Memory, Skills, Settings, Agents, Activity, Connectors, Rules, Browser), attachments, slash commands, the browser take-over, notifications and an offline copy. Use the web app for those.

## Setup

1. gaidin runs with `tailscale serve` in front of it, as its `docs/surfaces.md` says, and the iPhone runs Tailscale, signed in as gaidin's owner (`web.user` in gaidin's settings). The app sends nothing to sign in: `tailscale serve` adds your tailnet login to each request, and gaidin checks it.
2. Install the app on a paired iPhone (needs Xcode, XcodeGen and an Apple Development certificate): `sh scripts/install-device.sh`.
3. In the app, give the machine's tailnet name, such as `gaidin.example.ts.net`. Change it later from the foot of the sidebar.

## Layout

| Path | What |
|---|---|
| `MoiraineCore/` | SwiftPM package: gaidin's API types, the event stream, the transcript reducer (from moiraine's `src/transcript.ts`), the log's lines (from `src/conversation/log.tsx`), formatting, and the Markdown parser. No UIKit or SwiftUI. |
| `App/` | The SwiftUI app. `Theme.swift` is moiraine's `tokens.css`, its OKLCH colors converted in code. |
| `UITests/` | UI tests against gaidin's faux server. |
| `fixtures/` | Event streams recorded from gaidin's faux server, with the snapshot gaidin had at the end, for the reducer's tests. |
| `scripts/dev-faux.ts` | gaidin's e2e server (a scripted model, no keys, a throwaway data directory) behind a proxy that adds `Tailscale-User-Login`, as `tailscale serve` does. |
| `project.yml` | XcodeGen spec. `Moiraine.xcodeproj` is generated; don't edit it. |
| `design/` | The icon's source: Recraft's draft (`moiraine-draft.png`, its request in `moiraine-draft.recraft.json`, draft 02 of four) and its recolor to indigo `#818cf8` (`moiraine-indigo.png`), in the style of gaidin's agent avatars. |

`JSONValue.swift`, `Markdown.swift`, `Reveal.swift` and their tests come from [amyrlin](https://github.com/brad-j/amyrlin)'s core. The fonts are Fira Sans and Fira Code, under the SIL Open Font License (`App/Fonts`). The icons are [Phosphor](https://phosphoricons.com)'s, as the web app's are: the SVGs of the ones the app uses, copied from `phosphor-icons/core` into `App/Assets.xcassets/Phosphor` (MIT, `App/Icons-LICENSE.txt`), and named in `App/Icon.swift`. A new icon is added there both ways.

## Commands

Development needs gaidin checked out beside this directory (`../gaidin`, with `pnpm install` run there).

```sh
# Core tests
cd MoiraineCore && swift test

# The UI tests: starts gaidin's faux server on port 8421, runs them on a simulator, stops it
sh scripts/e2e.sh

# The app against gaidin's faux server in a simulator: start the server, then build and run with -server
node --no-warnings scripts/dev-faux.ts      # http://127.0.0.1:8420; FAUX_TOKENS_PER_SECOND=60 streams answers
xcodegen generate
xcodebuild -project Moiraine.xcodeproj -scheme Moiraine -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData build
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Moiraine.app
xcrun simctl launch booted io.bradjohnson.moiraine -server http://127.0.0.1:8420

# Record the fixtures again, with the faux server running (once with FAUX_TOKENS_PER_SECOND=40 for "streaming")
node --no-warnings scripts/record-fixtures.ts whole

# On a paired iPhone
sh scripts/install-device.sh
```

macOS has no bubblewrap, which gaidin's server needs, so `dev-faux.ts` puts `scripts/stub-bwrap` first on its path: it runs nothing, so a shell tool call fails, and the faux model never makes one.

## License

MIT, in [LICENSE](LICENSE).
