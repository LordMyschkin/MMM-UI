# MMM-UI · Martins MacOS Music UI

A native SwiftUI macOS music player inspired by A-mpd. The first macOS app menu lets you switch between **Local Files** and **MPD Client**. Both modes provide a compact Now Playing panel, queue, library browser, search, settings, and random queue filling.

## Build

Requires macOS 14 or newer and the Swift Command Line Tools. From this directory:

```sh
./build-app.sh
open dist/MMM-UI.app
```

The build creates `dist/MMM-UI.app`. It uses no external package dependencies. The app is ad hoc signed; downloaded copies may trigger a Gatekeeper warning because they are not notarized.

## Controls

- Double-click a queue row to play; drag a row to reorder it.
- Choose **Local Files…** or **MPD Client** from the first macOS menu, **MMM-UI**. Local mode works without an MPD server and reads audio files recursively from a chosen folder. You can change the folder from the same menu.
- Use Queue, Library, and Search from **Navigate**. Open the separate **Settings…** popup from **MMM-UI** (⌘,).
- The **Playback** menu and macOS media keys control the active player in either mode.
- Search **Next** inserts behind the current track. The Library offers Next and Add.
- In Local Files mode, folders in Library offer **Next** and **Add** for all audio tracks below them. **Add folder** in the header adds the currently open folder tree.
- Settings can display the composer and file path, configure the connection in MPD mode, and keep a chosen number of random library tracks in the queue. The sidebar offers **Fill to 200 random tracks** in either mode.
- The optional **Show track changes by the camera for 2 seconds** setting briefly displays the new title in a small overlay at the top of the screen. It is an app overlay near the Mac camera, not a system Dynamic Island API.
- Local mode quits immediately and stops local playback. In MPD mode, MMM-UI can optionally ask whether to pause MPD. Queue filling stops when the app exits; MPD retains its queue.

Settings and the local queue are stored in `~/Library/Application Support/s-mpc/settings.json` for compatibility with existing installations. Local and MPD shuffle settings are separate, and the local queue is restored when switching modes or restarting the app. On first launch, connection and display settings are read from A-mpd if present. Automatic filling starts disabled, so both apps can be installed without competing for the same queue. The MPD password remains in memory for the current session. Local files stay on this Mac; MMM-UI does not upload or index them in an external service.
