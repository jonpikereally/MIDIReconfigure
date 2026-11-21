# MIDI Reconfigure

MIDI Reconfigure is a macOS menu bar utility that remaps incoming MIDI and publishes the result as a virtual input for your DAW. It uses CoreMIDI and runs locally on macOS 14 Sonoma or later.

## Route MIDI to your DAW

1. Open **MIDI Reconfigure.app** and click its menu bar icon.
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
| `MIDI-201` | Saved routing settings could not be read. The app loaded defaults. |
| `MIDI-202` | Changes could not be saved. Try saving them again before quitting. |
| `RULE-001` | A rule’s note, CC, or program number must be a whole number from 0 to 127. |

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
