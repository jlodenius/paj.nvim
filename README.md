# paj.nvim

Neovim client for the [Paj](https://github.com/jlodenius/paj) Unix-socket bridge. It discovers live Pi sessions for the current Git repository, sends prompts without terminal scraping, and renders streamed assistant output in a scratch buffer.

## Requirements

- Neovim 0.10 or newer
- `paj` on `PATH`
- A live Pi session with the Paj extension and bridge enabled

Verify the bridge before configuring Neovim:

```sh
paj session list
paj bridge status <agent>
```

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

## Commands

| Command | Description |
| --- | --- |
| `:PajSessions` | Select the target Pi session for the current repository |
| `:PajAttach` | Alias for selecting the target session |
| `:PajPrompt [prompt]` | Send a prompt; opens an input when no argument is given |
| `:[range]PajExplain [focus]` | Explain the selected lines, or the current line |
| `:[range]PajReview [focus]` | Review the selected lines, or the entire buffer |

Examples:

```vim
:PajPrompt Explain the repository architecture
:'<,'>PajExplain focus on ownership
:%PajReview focus on error handling
```

When exactly one bridged session is available, it is selected automatically. With multiple sessions, Paj uses `vim.ui.select`; picker plugins such as Dressing can customize that interface.

## Configuration

```lua
require("paj").setup({
  command = "paj",
  timeout = 300,
  output_height = 14,
  max_prompt_bytes = 200 * 1024,
})
```

Prompts containing buffer content are written to a private temporary file and passed through `paj bridge prompt --prompt-file`. The temporary file is removed when the client exits.

Paj rejects a request when the selected Pi session is already working. Wait for the current turn to settle, then retry.

## Development

```sh
stylua --check lua plugin tests
nvim --headless -u NONE -l tests/headless.lua
```
