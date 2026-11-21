# paj.nvim

Ask Pi about your code or review it from Neovim. Replies appear in a Markdown scratch buffer.

Requires Neovim 0.10+, the [Paj CLI on `PATH` and the Paj Pi extension](https://github.com/jlodenius/paj#install),
and a live Pi session with an editor bridge. Update the CLI, extension, and plugin together.

## Installation

With `lazy.nvim`:

```lua
{
  "jlodenius/paj.nvim",
  config = true,
}
```

With `vim.pack` (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/jlodenius/paj.nvim" })
require("paj").setup()
```

Or add the repository to `runtimepath` and call `require("paj").setup()`.

## Usage

Start Pi in the same project as your buffer. If Pi was already open when you installed Paj,
run `/reload` in Pi. In Neovim, run `:%PajReview` and look for the reply in a scratch buffer.

- `PajQuery`, `PajExplain`, and `PajReview` send the current text, including unsaved changes.
  Use a range for selected lines; without one, they use the whole buffer. In the query editor,
  use `:write` to send.
- `:PajSessions` (or `:PajAttach`) selects a bridged session. The plugin prefers main sessions.
- In a reply, press `f` to follow up in the same Pi session or `q` to cancel or close.

Queries, reviews, and follow-ups cannot edit files. Press `a` to authorize an edit-capable turn
for a proposal. **Accepted** means the bridge acknowledged it, not that the edit succeeded.
You can retry a definite busy rejection manually; the plugin does not replay a disconnect.

If no session appears, run `paj --json session list` from the buffer's project.
Registration alone does not mean the editor bridge is available.

## Reference

[Session selection, configuration, troubleshooting, and development](docs/reference.md).
