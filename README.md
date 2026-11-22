# MIDI Reconfigure

MIDI Reconfigure is a macOS app that remaps incoming MIDI and publishes the result as a virtual input for your DAW. It uses CoreMIDI and runs locally on macOS 14 Sonoma or later.

## The main window

The main window holds everything: **Routing**, **Functions**, **Activity**, **Settings**, and **Errors** in the sidebar. It opens at launch when the app is shown in the Dock. You can also open it from the menu bar icon, from **Window › Main Window** (⌘0), or by clicking the Dock icon. ⌘1–⌘5 switch sections, and ⌘, opens Settings.

In **Settings › App**, choose **Show in Dock**, **Show in menu bar**, or both. One of them always stays on, so the app can't become unreachable.

## Updates

MIDI Reconfigure checks this repository's GitHub Releases at launch and every few hours. **Settings › Updates** shows the installed version and build, the latest release notes, and a **Check for Updates** button. **Install … and Relaunch** downloads the new app, checks its signature, replaces the installed copy, and reopens it.

Turn on **Install updates automatically** to install a new version when the app launches. Updates never install while the app is already running, so a set is never interrupted. Keep the app in a folder you can write to, such as Applications.

To publish a release from the browser:

1. Open the repository's **Actions** tab and choose **Release**.
2. Click **Run workflow**. Leave **Version** empty to use the version in `Packaging/Info.plist`, or enter one such as `1.3.1`.
3. Click the green **Run workflow** button.

The workflow tests the code, builds a universal app, creates the `v<version>` tag, and attaches `MIDI-Reconfigure.zip` to a new GitHub release. Pushing a `v*` tag from Terminal does the same thing.

| Code | What to check |
| --- | --- |
| `REL-001` | The version must look like `1.3.0`. |
| `REL-002` | That version is already released. Bump `CFBundleShortVersionString` in `Packaging/Info.plist`, or enter a new version. |

## Route MIDI to your DAW

1. Open **MIDI Reconfigure.app**.
2. Open **Routing** and enable the input ports you want to route. Each enabled input passes through by default.
3. Set a **Default output channel** or add a rule. Rules run from top to bottom and the first enabled match applies. A rule can match an input port, channel, message type, and where applicable, the note, CC, or program number.
4. Select **MIDI Reconfigure** as a MIDI input in your DAW. Select that input on your track if your DAW also listens to the original device.

In the rule editor, click **MIDI Learn** and play a note, move a control, or send a Program Change from an enabled input. The editor fills in the device, channel, type, and number from that message. Set the action and save the rule when ready. MIDI Learn also works while routing is paused.

Examples

| Match | Action |
| --- | --- |
| Any message on channel 1 | Send on channel 10 |
| Note 36 | Send note 48 with the original velocity |
| CC 11 | Send CC 74 and invert the value (0 → 127) |
| Program Change 5 | Send Program Change 12 |
| Any Program Change from a specific port | Block the message |

Channels are numbered 1–16. Note, CC, and Program Change use the MIDI wire numbers 0–127. A DAW or controller that displays programs as 1–128 may show a different label for the same program.

Rules operate on MIDI 1.0 channel messages. Clock, system messages, and SysEx pass through from enabled inputs. While routing is paused, enabled inputs remain visible in Activity. Routing settings survive a relaunch.

## Output functions

A function is a saved MIDI command with a name, such as **AbleSet Play** or **Quad Cortex Tuner**. The **Functions** page holds your library. Each function stores:

- the message to send: a Note, Control Change, or Program Change, with its channel, number, and either a fixed value/velocity or **Use the input’s value**
- a destination: the **MIDI Reconfigure** virtual port (the default, for Ableton Live, AbleSet, and other apps) or any connected hardware MIDI destination, such as the Quad Cortex over USB

To use a function:

1. In **Routing**, click **Load function** and pick one from the library. MIDI Learn starts right away.
2. Press the footswitch, pad, or key that should trigger it. Adjust the device, channel, type, or number if needed, then save the mapping.
3. Click ▶ on any function to send its output once and check it.

Mapped inputs run before the routing rules. A matched message sends its function and isn’t passed to the rules. A fixed-value function fires on the press (Note On, CC value above 0, or any Program Change) and ignores the release. A Note output triggered by a note holds until you release that note. Triggered by a CC or Program Change, it sends a Note On and Note Off together.

Loaded functions stay linked to the library. Edit a function’s output or destination once, and every mapping that uses it changes. Deleting a function from the library also removes its mappings from Routing.

The starter functions (AbleSet Play, Stop, Next Song, Previous Song, and Quad Cortex Tuner) send **placeholder** messages and show a **Verify** badge. Set each one to the message configured in AbleSet’s MIDI settings or the Quad Cortex’s MIDI settings, then turn off **Placeholder**. **Restore missing starter functions** in the library’s ••• menu adds back any starter you deleted.

## Inspect MIDI

**Activity** shows the latest 600 incoming and outgoing events from enabled ports. Filter by direction, sort by recent time, device, or message type, and pause the display while you inspect a message. **Errors** shows diagnostic codes and build information.

## Error codes

| Code | What to check |
| --- | --- |
| `MIDI-101` | CoreMIDI failed to start. Use **Restart MIDI** in Errors. |
| `MIDI-102` | The virtual output could not be created. Restart MIDI and check your DAW’s input list. |
| `MIDI-103` | The input port could not be created. Use **Restart MIDI**. |
| `MIDI-104` | An enabled input could not connect. Reconnect the device and refresh Inputs. |
| `MIDI-105` | An event could not be sent. Restart MIDI and reselect the input in your DAW. |
| `MIDI-106` | The output port’s stored identity was unavailable. Reselect the virtual input if your DAW lost it. |
| `MIDI-107` | The hardware output port could not be created. Functions can only use the virtual port. Use **Restart MIDI**. |
| `MIDI-108` | A function’s hardware destination is offline. Reconnect the device or choose another destination. |
| `MIDI-109` | A message could not be sent to a hardware destination. Reconnect the device and use **Restart MIDI**. |
| `MIDI-201` | Saved routing settings could not be read. The app loaded defaults. |
| `MIDI-202` | Changes could not be saved. Try saving them again before quitting. |
| `MIDI-203` | The function library could not be read. The starter library loaded, and the unreadable copy was kept as a backup. |
| `MIDI-204` | Function library changes could not be saved. Try again before quitting. |
| `RULE-001` | A rule’s note, CC, or program number must be a whole number from 0 to 127. |
| `FUNC-001` | A function needs a name, a number from 0–127, a value from 0–127 (velocity 1–127), and a channel from 1–16. |
| `FUNC-002` | A function mapping’s input number must be a whole number from 0 to 127, or empty for any. |
| `FUNC-003` | A loaded function is no longer in the library. Remove it from Routing, or load it again. |
| `UPD-001` | Updates couldn't be checked. Check your internet connection and try **Check for Updates** again. |
| `UPD-002` | No published release was found. See the GitHub Releases page. |
| `UPD-003` | The update couldn't be downloaded or unpacked. Try again, or download it from GitHub Releases. |
| `UPD-004` | The update couldn't be installed. Move the app to a folder you can edit, such as Applications. |
| `UPD-005` | Updates install only into a packaged app built with `scripts/build-app.sh`. |
| `APP-001` | The Dock icon and menu bar icon can't both be hidden. |

## Build from source

Install Xcode or the Xcode Command Line Tools. The build has no third-party dependencies.

```sh
git clone https://github.com/jonpikereally/MIDIReconfigure.git "$HOME/Documents/MIDIReconfigure"
cd "$HOME/Documents/MIDIReconfigure"
swift test
./scripts/build-app.sh
open "dist/MIDI Reconfigure.app"
```

The script produces the app and a ZIP in `dist/`. The default build targets the current Mac architecture. Pass `--universal` to build for Apple silicon and Intel. The default app signature is ad hoc for local use.
