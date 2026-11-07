# GlassCue

A native, private teleprompter for Apple silicon Macs running macOS 26 or later.

## Start a take

1. Open **GlassCue.app**. You can keep it in this folder or move it to Applications.
2. Type or paste your script, or choose **Link Markdown…** and select a note in your Obsidian vault. The picker starts at `~/Vault` when available.
3. Choose **Show overlay**. Drag its top bar to place it near the camera; drag its lower-right corner to resize it. The script is center-aligned. Adjust **Text size**, then use **Reading position** to move the active line higher or lower within the overlay. Smaller percentages place it higher; larger percentages place it lower. This setting updates immediately and is remembered between launches. A **Background** value of zero means genuinely transparent.
4. Turn **Position & resize** off to remove the frame and let clicks pass through to OBS, CapCut, or any app underneath.
5. With **Voice follow** selected, click **Start listening** and allow microphone access when macOS asks. Apple may need to download a speech model on first use. The app uses the microphone selected in **System Settings → Sound → Input**.
6. Start recording in your recording app, then read naturally. The mint word marks the last matched word. Pause or go off script: the text holds its place. Return to a recognizable phrase and it follows again.

There is no subscription, account, cloud transcription, saved audio, or network service in GlassCue. Apple's operating system downloads language models when needed; speech analysis runs on the Mac.

## Voice matching

The follower compares a recent phrase against the script ahead of your current position. It tolerates a small number of omitted or misrecognized words in longer phrases. Two recognizable words can advance nearby text; larger jumps need at least four words and meaningful content. A lone shared word or common filler does not trigger a jump. Longer, distinctive phrases help it find you after a digression.

It moves forward automatically. To repeat an earlier passage, enable **Position & resize** and click the word where you want to resume. **Back to beginning** resets a take. If recognition loses your place, speak the next distinctive phrase or click your place. Repeated or nearly identical passages can be ambiguous.

This is phrase-based following with recognition latency, not instantaneous word-by-word prediction. The microphone meter indicates input; the **Heard** line shows recent recognized words. **Listening · holding your place** is normal during silence or a digression.

**Auto scroll** is an optional fixed-speed mode. Voice follow never substitutes timed scrolling when it cannot find a match.

## Keyboard shortcuts

These work while other apps are active, without Accessibility permission:

| Action | Shortcut |
|---|---|
| Start / pause | Control–Option–Space |
| Show / hide overlay | Control–Option–O |
| Close overlay and pause listening | Escape |
| Position mode / click-through | Control–Option–L |
| Back to beginning | Control–Option–R |

All actions are also in the GlassCue menu bar icon. To close the floating script, press **Escape** or **Control–Option–O**, click **Hide overlay**, or click the **×** at the top right of its positioning bar. Hiding the overlay also pauses listening. Escape works from other apps, including in click-through mode, and is released back to other apps as soon as the overlay closes. In click-through mode, press **Control–Option–L** to bring back the positioning bar and its close button. Closing the controls leaves the app available in the menu bar. Use **Quit GlassCue** to stop the microphone and exit.

## Obsidian and Markdown

Linking is read-only. GlassCue checks the chosen UTF-8 file once a second, including saves that replace the file atomically. Headings, emphasis, links, wiki-link aliases, and task markers become readable text. YAML frontmatter, comments, fenced code, and image/note embeds are omitted. Embedded notes are not expanded.

Changes to the script pause a running take and reset its position so it cannot silently follow stale word locations. If a note disappears, the last loaded text remains and the app shows a file status message. Choose **Detach** to edit a local copy without changing the source note. Script text, linked path, and appearance settings are saved locally between launches.

## Recording with OBS or CapCut

The overlay stays above normal app windows and can join full-screen spaces. It does not start or modify recordings. Use the recording app normally with click-through enabled.

**A transparent overlay can still appear in a full-display recording.** GlassCue does not promise capture exclusion on macOS 26. If the script should stay out of the final video, record the camera or a specific app/window that excludes GlassCue, and check a short test recording with your actual capture configuration.

## Troubleshooting

- No microphone input: check **System Settings → Sound → Input**, and allow GlassCue under **Privacy & Security → Microphone**. Pause and restart after changing input devices.
- First start says it is preparing or downloading: let Apple's speech model installation finish. This requires an internet connection on first use. You can cancel preparation from the main button.
- Language unavailable: choose another supported language. The app reports unavailable on-device speech rather than silently sending audio to a server.
- A shortcut is already reserved by another app: use GlassCue's menu bar controls.
- Cannot find the overlay: show it from the menu bar. Its position is restored across launches when it intersects an attached screen.

## Source and rebuild

The complete Swift sources are in `Source/`. No third-party packages are required. With Apple Command Line Tools installed, run:

```sh
./build.sh
./GlassCue.app/Contents/MacOS/GlassCue --self-test
```

The build is locally ad-hoc signed, not an App Store or notarized distribution. macOS may require you to approve a downloaded build in System Settings → Privacy & Security; alternatively, build from source. Its minimum system version is macOS 26 and its architecture is arm64.

Design reference: [Speakflow Desktop's floating overlay](https://www.speakflow.com/docs/speakflow-desktop-app). Speech engine: [Apple SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/). GlassCue is an independent app.
