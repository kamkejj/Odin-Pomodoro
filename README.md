# Pomodoro

A minimal, high-performance Pomodoro timer written in **Odin** using **Metal** for graphics on macOS.

> [!IMPORTANT]
> **LLM Assistance Disclaimer**: This project was developed with significant assistance from a Large Language Model (LLM).

## Features

- **Metal-accelerated UI**: Smooth rendering using macOS native graphics API.
- **Top-most window**: Stays on top of other windows to keep you focused.
- **Configurable**: Setup your work and break durations via CLI flags or a JSON settings file.
- **Automatic Transitions**: Automatically cycles between Work, Short Break, and Long Break (after 4 pomodoros).

## Building

### Prerequisites

- [Odin compiler](https://odin-lang.org/news/installing-odin/)
- macOS with Metal support
- SDL2 (`brew install sdl2`)

### Build Instructions

Use the provided `Makefile` to build the project:

```bash
make build
```

The executable `pomodoro` will be generated in the project root.

## Running

You can run the application directly or via `make`:

```bash
make run
```

### Controls

- `Space`: Pause / Resume timer.
- `S`: Skip to the next state.
- `Cmd + ,`: Open settings UI (requires Swift).
- `Cmd + Q`: Quit (standard macOS window close).

### Configuration

The app loads settings from `~/.pomodoro_settings.json`. You can also pass flags:

```bash
./pomodoro -work:25 -short_break:5 -long_break:15
```
