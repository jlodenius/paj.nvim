# paj.nvim

Neovim client for the [Paj](https://github.com/jlodenius/paj) Unix-socket bridge. It discovers live Pi sessions for the current project, sends editor context without terminal scraping, and streams responses into a scratch buffer.

## Requirements

- Neovim 0.10 or newer
- `paj` on `PATH`
- A live Pi session with the Paj extension enabled

## Installation

With `lazy.nvim`:

```lua
{
  "jlodenius/paj.nvim",
  config = true,
}
```

With `vim.pack`:

```lua
vim.pack.add({ "https://github.com/jlodenius/paj.nvim" })
require("paj").setup()
```

Or add the repository to `runtimepath` and call `require("paj").setup()`.

## Usage

Start Pi in the same project as Neovim, then send a prompt:

```vim
:PajPrompt Explain the repository architecture
```

Paj selects the only available session automatically. When multiple sessions are available, it opens `vim.ui.select` with each session's name, role, status, branch, and task. The selection is remembered per project. Use `:PajSessions` to choose a different session.

### Commands

| Command | Description |
| --- | --- |
| `:PajSessions` | Select the target Pi session for the current project |
| `:PajAttach` | Alias for `:PajSessions` |
| `:PajPrompt [prompt]` | Send a prompt, opening an input when no argument is given |
| `:[range]PajExplain [focus]` | Explain the selected lines, or the current line without a range |
| `:[range]PajReview [focus]` | Review the selected lines, or the entire buffer without a range |

Examples:

```vim
:'<,'>PajExplain focus on ownership
:%PajReview focus on error handling
:PajReview focus on concurrency
```

`PajExplain` and `PajReview` include the source path, line range, and selected buffer content in the prompt. Responses stream into a temporary Markdown scratch buffer.

## Configuration

```lua
require("paj").setup({
  command = "paj",
  timeout = 300,
  output_height = 14,
  max_prompt_bytes = 200 * 1024,
})
```

| Option | Description |
| --- | --- |
| `command` | Paj executable name or path |
| `timeout` | Bridge request timeout in seconds |
| `output_height` | Height of the response split |
| `max_prompt_bytes` | Maximum prompt size accepted by the plugin |

Prompts are written to a private temporary file and passed through `paj bridge prompt --prompt-file`. The file is removed when the bridge client exits.

## Troubleshooting

### No live sessions

Check that Pi is running with the Paj extension in the same Git repository:

```sh
paj --json session list
```

Session discovery is project-scoped. Neovim uses the current buffer's Git root, falling back to its working directory outside a Git repository.

### Session has no bridge

Inspect the selected session:

```sh
paj bridge status <session>
```

If it is unavailable, confirm that the Pi session loaded the Paj extension and that its registration is healthy.

### Session is busy

A Pi session handles one bridge request at a time. Wait for its current turn to finish, then retry, or select another session with `:PajSessions`.

### Request times out

Increase `timeout` in `setup()` for prompts that need longer to complete. The value is forwarded to `paj bridge prompt --timeout`.

## Development

```sh
stylua --check lua plugin tests
nvim --headless -u NONE -l tests/headless.lua
```
