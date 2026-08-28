# Mied

A small, distraction-free multi-document text editor built on Tcl/Tk and the
[`ctext`](https://core.tcl-lang.org/tklib/) widget.

<img src="./img/preview.png" width="900">

## Features

- Multiple buffers
- Syntax highlighting for Tcl, C, and shell scripts
- Line numbers, status bar with cursor position, and language indicator
- Find and replace (with case-sensitive toggle)
- Comment toggling (`#` / `//` based on detected language)
- Smart indent / outdent and return-indent
- Tear-off editor windows you can move and resize freely

## Requirements

- Tcl/Tk 8.5 or newer
- Tklib (`ctext` widget)

## Usage

```sh
wish mied.tcl
```

## Hotkeys

| Key                  | Action                                |
| -------------------- | ------------------------------------- |
| `Ctrl`+`N`           | New untitled buffer                   |
| `Ctrl`+`O`           | Open file…                            |
| `Ctrl`+`S`           | Save                                  |
| `Ctrl`+`B`           | Toggle sidebar                        |
| `Ctrl`+`F`           | Show find bar                         |
| `Ctrl`+`Tab`         | Next buffer                           |
| `Ctrl`+`Shift`+`Tab` | Previous buffer                       |
| `Ctrl`+`S`           | Save                                  |
| `Ctrl`+`W`           | Close buffer                          |
| `Ctrl`+`L`           | Select current line                   |
| `Ctrl`+`/`           | Toggle `#`/`//` comment               |
| `Enter`              | Re-indent new line (preserves indent) |
| `Tab`                | Indent selection / current line       |
| `Shift`+`Tab`        | Outdent selection / current line      |


### Find bar

| Key               | Action                    |
| ----------------- | ------------------------- |
| `Enter` (Find)    | Find next match           |
| `Enter` (Replace) | Replace match + find next |
| `Escape`          | Hide find bar             |

Mouse buttons on the find bar:

| Button  | Action                |
| ------- | --------------------- |
| `Aa`    | Toggle case-sensitive |
| `<`     | Find previous match   |
| `>`     | Find next match       |
| `Repl`  | Replace & find next   |
| `ReAll` | Replace all matches   |
| `x`     | Close find bar        |

### Toolbar buttons

| Button  | Action              |
| ------- | ------------------- |
| New     | New untitled buffer |
| Open    | Open file…          |
| Save    | Save                |
| Save As | Save as…            |
| Buffers | Toggle sidebar      |
| About   | About dialog        |
