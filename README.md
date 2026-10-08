# llm-hotkey

Select text in any macOS app, press a hotkey, and the selection is replaced with the LLM's result. Works with **OpenAI** and **Gemini**.

| Action    | Hotkeys                          | What it does                                      |
|-----------|----------------------------------|---------------------------------------------------|
| translate | ⌘⌥T, **fn+F5**                   | Russian → English, anything else → Russian        |
| grammar   | ⌘⌥G, **fn+F6**                   | Fixes grammar/spelling with minimal changes       |
| rephrase  | ⌘⌥R                              | Rewrites the text more clearly                    |
| speak     | ⌘⌥S (press again to stop)        | Reads the selection aloud (OpenAI TTS or system voice) |

While the LLM is working, a clock ticks and the menu-bar icon turns into an hourglass. On error you hear a sound and the icon shows ⚠️; details are printed to the terminal.

## How it works

1. The hotkey is caught via Carbon `RegisterEventHotKey`, so there is no global `CGEventTap` that macOS could time out or disable.
2. Waits until you release the modifiers, then sends ⌘C from a private event source (key down + key up), so held keys don't leak in.
3. Waits for the pasteboard to change (no fixed sleep), sends the text to the selected provider.
4. Pastes the result with ⌘V, then **restores your previous clipboard contents**.

## Build & run

```bash
./build.sh          # swiftc → ./text_hotkey
./text_hotkey       # keep it running; an icon appears in the menu bar
```

Requires macOS 12+ and the Xcode command line tools.

**Accessibility permission** is required to send ⌘C/⌘V: System Settings → Privacy & Security → Accessibility. If you run the binary from a terminal, grant it to the terminal app.

## Configuration

On first run a config is created at `~/.config/text-hotkey/config.json` (see [`config.example.json`](config.example.json)):

- `provider`: `"openai"` or `"gemini"` (can also be switched from the menu-bar icon)
- `openai_api_key`, `gemini_api_key`: or use the `OPENAI_API_KEY` / `GEMINI_API_KEY` environment variables
- `openai_model`, `gemini_model`
- `restore_clipboard`: put the previous clipboard contents back after pasting
- `actions.<name>.hotkeys`: e.g. `"cmd+opt+t"`, `"ctrl+shift+x"`, `"f5"` (modifiers: `cmd`, `opt`, `ctrl`, `shift`)
- `actions.<name>.prompt`: the system prompt for that action

After editing, use **Reload config** in the menu.

### Why fn+F5 and not fn+letter?

`fn` can't be a modifier for system hotkeys; only a global event tap can see it, and that is exactly the fragile approach this app avoids. On a MacBook, fn+F5 sends a plain F5, which can be registered as a normal hotkey. Change it in the config if F5/F6 don't suit you.

## Ticking sound

`ticking.mp3` is loaded from next to the binary, or from `~/.config/text-hotkey/`. Without it, everything still works, just silently.
