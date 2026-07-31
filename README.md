# paj.nvim

Neovim client for the [Paj](https://github.com/jlodenius/paj) Unix-socket bridge. It discovers live Pi sessions for the current project, sends editor context without terminal scraping, and streams responses into a scratch buffer.

## Requirements

- Neovim 0.10 or newer
- A current `paj` CLI on `PATH`
- A live Pi session with the current Paj extension enabled

The CLI, extension, and plugin must be updated together; older Paj versions do not provide the native structured actions this plugin expects.

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

Paj selects the only available session automatically. When multiple sessions are available, it opens `vim.ui.select` with each session's name, role, branch, and task. The selection is remembered per project. Use `:PajSessions` to choose a different session.

### Commands

| Command | Description |
| --- | --- |
| `:PajSessions` | Select the target Pi session for the current project |
| `:PajAttach` | Alias for `:PajSessions` |
| `:PajPrompt [prompt]` | Send a prompt, opening an input when no argument is given |
| `:[range]PajQuery` | Open an editable floating query for the selected lines or entire buffer; write it to send |
| `:[range]PajExplain [focus]` | Explain the selected lines, or the entire buffer without a range |
| `:[range]PajReview [focus]` | Review the selected lines, or the entire buffer without a range |

Examples:

```vim
:'<,'>PajQuery
:'<,'>PajExplain focus on ownership
:%PajReview focus on error handling
:PajReview focus on concurrency
```

`PajQuery` opens a centered multiline floating buffer with a `:w=submit q=cancel` footer. Enter a question and use `:write` to send it, or press `q` in normal mode to cancel. The sent prompt clearly separates the query from the source context.

`PajQuery`, `PajExplain`, and `PajReview` include the source path, line range, and buffer content as escaped, explicitly untrusted JSON data. With no range they use the entire current buffer. Responses stream into a temporary Markdown scratch buffer.

While a request is running, use buffer-local `:PajCancel` or press `q` to cancel it. Press `q` again to close the output, or use buffer-local `:PajClose` to cancel and close immediately.

Every completed response shows a sticky action footer pinned to the bottom of its output window and supports a follow-up with `f` or buffer-local `:PajFollowUp`. This opens the same multiline editor and sends the question to the same Pi session. Paj supplies proposed changes as native structured actions alongside ordinary Markdown response text; the plugin does not parse hidden Markdown metadata. When a response includes one or more proposals, the footer shows an accept action. Press `a` or run buffer-local `:PajAccept`; when there are multiple proposals, select one with `vim.ui.select`. Follow-up questions, accepted changes, and subsequent agent responses are appended to the existing output buffer as a conversation. Closing a response without accepting simply leaves its proposals unimplemented.

## Configuration

```lua
require("paj").setup({
  command = "paj",
  timeout = 300,
  output_size = 30,
  output_position = "bottom",
  max_prompt_bytes = 200 * 1024,
})
```

| Option | Description |
| --- | --- |
| `command` | Paj executable name or path |
| `timeout` | Bridge request timeout in seconds |
| `output_size` | Response split size as a percentage from `1` to `100` |
| `output_position` | Response split position: `"top"`, `"bottom"`, `"left"`, or `"right"` |
| `max_prompt_bytes` | Maximum prompt size accepted by the plugin |

For top and bottom splits, `output_size` is a percentage of the editor height. For left and right splits, it is a percentage of the editor width.

Prompts are piped directly to `paj bridge prompt --prompt-stdin`; they are not stored in temporary files.

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

A Pi session handles one bridge request at a time. Wait for its current turn to finish, cancel the request from its output buffer, or select another session with `:PajSessions`.

### Cancel a request

In the request's output buffer, run `:PajCancel` or press `q`. Cancellation stops the Paj bridge client and asks the connected Pi session to abort that bridge request. Closing or wiping a running output buffer also cancels it.

### Request times out

Increase `timeout` in `setup()` for prompts that need longer to complete. The value is forwarded to `paj bridge prompt --timeout`.

## Development

```sh
stylua --check lua plugin tests
nvim --headless -u NONE -l tests/headless.lua
```
