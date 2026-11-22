<div align="center">
  <img width="225" height="225" src="/assets/graphics/Classic.png" alt="Logo">
  <h1><b>Loop</b></h1>
  <p>Window management made elegant.<br>
  <a href="https://github.com/MrKai77/Loop#features"><strong>Explore Loop »</strong></a><br><br>
  <a href="https://github.com/MrKai77/Loop/releases/latest/download/Loop.zip">Download for macOS</a><br>
  <i>~ Compatible with macOS 13 and later. ~</i></p>
</div>

Loop is a macOS app that simplifies window management for you. You can effortlessly choose your window direction using a radial menu triggered by a simple key press, and customize it according to your preferences with personalized colors and settings. You can easily move, resize, and arrange your windows with just a few clicks, saving you valuable time and energy.

> [!NOTE]
>
> Loop is constantly evolving, with new features and improvements added regularly to enhance your window management experience on macOS.

<h6 align="center">
  <img src="assets/graphics/loop_demo.gif" alt="Loop Demo">
  <br /><br />
  <a href="https://discord.gg/2CZ2N6PKjq">
    <img src="https://img.shields.io/badge/Discord-join%20us-7289DA?logo=discord&logoColor=white&style=for-the-badge&labelColor=23272A" />
  </a>
  <a href="https://github.com/MrKai77/Loop/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/MrKai77/Loop?label=License&color=5865F2&style=for-the-badge&labelColor=23272A" />
  </a>
  <a href="https://github.com/MrKai77/Loop/stargazers">
    <img src="https://img.shields.io/github/stars/MrKai77/Loop?label=Stars&color=57F287&style=for-the-badge&labelColor=23272A" />
  </a>
  <a href="https://github.com/MrKai77/Loop/network/members">
    <img src="https://img.shields.io/github/forks/MrKai77/Loop?label=Forks&color=ED4245&style=for-the-badge&labelColor=23272A" />
  </a>
  <a href="https://github.com/MrKai77/Loop/issues">
    <img src="https://img.shields.io/github/issues/MrKai77/Loop?label=Issues&color=FEE75C&style=for-the-badge&labelColor=23272A" />
  </a>
  <br />
</h6>

## Features

### Radial Menu

The Radial Menu allows you to manipulate windows using your mouse/trackpad. Hold down the trigger key and move your cursor in the desired direction to move and resize the window.

<div><video controls src="https://github.com/user-attachments/assets/a1e28631-091d-4abe-8f6e-bbb3f1399e84" muted="false"></video></div>

### Preview

The preview window enables you to see the resize action *before* committing to it.

<div><video controls src="https://github.com/user-attachments/assets/2afdecea-39e8-4f25-8c12-9cfc8aacbe2e" muted="false"></video></div>

### Keyboard Shortcuts

Loop allows you to assign any key in tandem with the trigger key to initiate a window manipulation action.

<div><video controls src="https://github.com/user-attachments/assets/61c4a414-c5c4-4308-a533-4d5698578307" muted="false"></video></div>

### Cycles

Loop can become very powerful when paired with cycles. These enable you to perform multiple window manipulations in quick succession by pressing the same key combination repeatedly, or by left-clicking repeatedly!

<div><video controls src="https://github.com/user-attachments/assets/b4aee6d4-5110-447e-8ece-0cbeec864a08" muted="false"></video></div>

### Stash

Hide windows at the screen edge to declutter your workspace. Hover near the edge or use a keybind to access them whenever you need.

<div><video controls src="https://github.com/user-attachments/assets/080ba2fb-41b3-4b39-9000-a76f2fc794ed" muted="false"></video></div>

### Theming

#### Radial Menu

The radial menu is fully customizable in terms of width, shape, and color. It is also completely optional and can be disabled. Both the cursor interaction and the radial menu itself are independently toggleable.

<div><video controls src="https://github.com/user-attachments/assets/f95349fd-cbb3-4c83-a687-d7fea4345bc6" muted="false"></video></div>

#### Preview

Adjust the padding, corner radius, border color, and border width of the optional preview window.

<div><video controls src="https://github.com/user-attachments/assets/0cf27809-1fa3-4230-88be-5c60636fd885" muted="false"></video></div>

## Usage

### Installation

#### Homebrew

```bash
brew install loop
```

#### Manual Download

Navigate to the [release page](https://github.com/MrKai77/Loop/releases/latest) and download the latest `.zip` file located at the bottom, or [click me](https://github.com/MrKai77/Loop/releases/latest/download/Loop.zip).

### Triggering

Loop uses a trigger key to function. This key must be held down or pressed to activate certain features within Loop. To access the radial menu, hold down the trigger key and move the cursor in the desired direction. Users who prefer keyboard shortcuts can assign a key to work with the trigger key, activating specific actions. The trigger key can be set in the "Behavior" tab of the "Settings" section. The trigger key can consist of one or multiple keys.

To set Caps Lock as your trigger key, you have two options:

#### a. Change System Settings

1. Go to System Settings → Keyboard → "Keyboard Shortcuts...".
2. In the "Modifier Keys" tab, remap `Caps Lock (⇪) key` to `(^) Control`.
3. Repeat this remapping process for every connected keyboard.
4. In Loop, select the `Right Control` key as your trigger.

#### b. Use an external App

- [Hyperkey](https://hyperkey.app/)
- [Karabiner Elements](https://karabiner-elements.pqrs.org/)

#### c. Shell/AppleScript

Loop can be controlled via shell commands or AppleScript using its URL scheme:

```bash
# Shell examples
open "loop://direction/right"     # Move window to right half
open "loop://action/maximize"     # Maximize window
open "loop://screen/next"         # Move to next screen

# AppleScript examples
osascript -e 'tell application "Loop" to activate'
osascript -e 'open location "loop://direction/left"'
```

You can also create custom scripts to chain multiple actions:

```bash
#!/bin/bash
# Example: Move window right and then maximize
open "loop://direction/right"
sleep 0.5
open "loop://action/maximize"
```

For a complete list of available commands:

```bash
open "loop://list/all"           # List all commands
open "loop://list/actions"       # List window actions
open "loop://list/keybinds"      # List custom keybinds
```

### Keyboard Shortcuts

<table>
  <thead>
    <tr>
      <th>Category</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>General</strong></td>
      <td>Fullscreen, Maximize, Almost Maximize, Centre, MacOS Centre, Minimize, Hide</td>
    </tr>
    <tr>
      <td><strong>Halves</strong></td>
      <td>Top Half, Bottom Half, Left Half, Right Half</td>
    </tr>
    <tr>
      <td><strong>Quarters</strong></td>
      <td>Top Left Quarter, Top Right Quarter, Bottom Left Quarter, Bottom Right Quarter</td>
    </tr>
    <tr>
      <td><strong>Horizontal Thirds</strong></td>
      <td>Right Third, Right Two Thirds, Horizontal Center Third, Left Two Thirds, Left Third</td>
    </tr>
    <tr>
      <td><strong>Vertical Thirds</strong></td>
      <td>Top Third, Top Two Thirds, Vertical Center Third, Bottom Two Thirds, Bottom Third</td>
    </tr>
    <tr>
      <td><strong>Screen Switching</strong></td>
      <td>Next Screen, Previous Screen, Left Screen, Right Screen, Top Screen, Bottom Screen</td>
    </tr>
    <tr>
      <td><strong>Window Manipulation</strong></td>
      <td>Larger, Smaller, Shrink Top, Shrink Bottom, Shrink Right, Shrink Left, Grow Top, Grow Bottom, Grow Right, Grow Left, Move Up, Move Down, Move Right, Move Left</td>
    </tr>
    <tr>
      <td><strong>More</strong></td>
      <td>Initial Frame, Undo, Custom, Cycle</td>
    </tr>
  </tbody>
</table>

## FAQ

### Comparison

<table>
  <thead>
    <tr>
      <th></th>
      <th>Loop</th>
      <th>macOS&nbsp;15+</th>
      <th>Rectangle&nbsp;Pro</th>
      <th>Rectangle</th>
      <th>Magnet</th>
      <th>Moom</th>
      <th>Swish</th>
      <th>BetterTouchTool</th>
      <th>Multitouch</th>
      <th>Hammerspoon</th>
      <th>Yabai</th>
      <th>Amethyst</th>
      <th>AeroSpace</th>
      <th>1Piece</th>
      <th>Wins</th>
      <th>MacsyZones</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Price</td>
      <td>Free</td>
      <td>Free</td>
      <td>$9.99</td>
      <td>Free</td>
      <td>$4.99</td>
      <td>$15.00</td>
      <td>$16.00</td>
      <td>$14.00</td>
      <td>$15.99</td>
      <td>Free</td>
      <td>Free</td>
      <td>Free</td>
      <td>Free</td>
      <td>Free</td>
      <td>$13.99</td>
      <td>Free</td>
    </tr>
    <tr>
      <td>Open&nbsp;Source</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Custom&nbsp;Frames</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Preview&nbsp;Window</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
    </tr>
    <tr>
      <td>Theming&nbsp;Options</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
    </tr>
    <tr>
      <td>Modifier&nbsp;+&nbsp;Mouse</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Modifier&nbsp;+&nbsp;Arrows</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Modifier&nbsp;+&nbsp;Trackpad</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Trackpad&nbsp;Gestures</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Padding&nbsp;/&nbsp;Margins</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Stashed&nbsp;Windows</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
    </tr>
    <tr>
      <td>Save&nbsp;Workspace</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Restore&nbsp;Initial&nbsp;Frame</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Pin&nbsp;Windows&nbsp;On&nbsp;Top</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
    </tr>
    <tr>
      <td>Snap&nbsp;Windows&nbsp;via&nbsp;Drag</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
    </tr>
    <tr>
      <td>Resize&nbsp;Adjacent&nbsp;Windows</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Action&nbsp;Sequences&nbsp;(Cycles)</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
    </tr>
    <tr>
      <td>Move&nbsp;Windows&nbsp;Across&nbsp;Screens</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
    </tr>
    <tr>
      <td>Switch&nbsp;Focus&nbsp;Between&nbsp;Windows</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
    </tr>
    <tr>
      <td>Scripting&nbsp;(URL&nbsp;/&nbsp;AppleScript&nbsp;or&nbsp;other)</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>✅</td>
      <td>✅</td>
      <td>❌</td>
      <td>❌</td>
    </tr>
  </tbody>
</table>

> Information was gathered from each app’s official website and other online sources and may be outdated.
> If you notice any inaccuracies, please open an issue or contact the maintainers.
> Special thanks to the [Definitive MacApp Comparisons](https://docs.google.com/spreadsheets/d/1HtJN4oQ6oBDFmFaF4Qeq5vCGEU1g-KB1DEz5Sp_OwXo/edit?gid=456166567#gid=456166567) spreadsheet.

### How to Contribute

For an extensive guide on how to contribute, check out the [contributing guide](CONTRIBUTING.md).

### License

This project is licensed under the [GNU GPLv3 license](LICENSE).
