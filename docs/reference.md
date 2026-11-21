# paj.nvim reference

[Back to setup](../README.md).

## Session selection

The plugin prefers bridged main Pi sessions (`primary` in Paj). When exactly one primary is
available, it is selected even if subagents are also running; when multiple primaries are available,
Paj opens `vim.ui.select` for those primary sessions and remembers the choice per project while it
remains a candidate. If the topology changes to a sole primary, that session is selected instead. If
no primary is available, Paj falls back to all bridged sessions for compatibility. Picker entries
show each session's name, role, branch, and task.

Use `:PajSessions` to explicitly choose any bridged session, including a subagent. That override is
remembered per project while Neovim is running; if the selected session disappears, normal primary
selection resumes.

## Commands and reply controls

Use `PajExplain [focus]` and `PajReview [focus]` to explain or review selected lines or the
whole buffer. `PajQuery` opens a multiline question editor; press `q` there to discard the draft.

In a reply buffer, `PajFollowUp` (`f`) asks the same Pi session a follow-up. `PajAccept` (`a`)
asks you to choose if there is more than one proposal. Closing without accepting does not
authorize edits.

## Configuration

```lua
require("paj").setup({
  command = "paj",
  timeout = 300,
  output_size = 30,
  output_position = "bottom",
  max_request_bytes = 200 * 1024,
})
```

| Option | Description |
| --- | --- |
| `command` | Paj executable name or path |
| `timeout` | Bridge request timeout in seconds |
| `output_size` | Response split size as a percentage from `1` to `100` |
| `output_position` | Response split position: `"top"`, `"bottom"`, `"left"`, or `"right"` |
| `max_request_bytes` | Maximum encoded editor request size accepted by the plugin |

For top and bottom splits, `output_size` is a percentage of the editor height. For left and right
splits, it is a percentage of the editor width.

Requests are encoded as JSON and piped directly to `paj bridge request --request-stdin`; they are
not stored in temporary files.

## Troubleshooting

### No live sessions

From the buffer's project, check that Pi is running with the Paj extension:

```sh
paj --json session list
```

Session discovery is project-scoped. Neovim uses the current buffer's Git root, falling back to its
working directory outside a Git repository. Registration alone does not mean the editor bridge is
available.

### Session has no bridge

Inspect the selected session:

```sh
paj bridge status <session>
```

If it is unavailable, confirm that the Pi session loaded the Paj extension and that its registration
is healthy.

### Session is busy

A Pi session handles one bridge request at a time. Wait for its current turn to finish, cancel the
request from its output buffer, or select another session with `:PajSessions`.

### Cancel a request

In the request's output buffer, run `:PajCancel` or press `q`. Cancellation stops the Paj bridge
client and asks the connected Pi session to abort that bridge request. Closing or wiping a running
output buffer also cancels it.

### Request times out

Increase `timeout` in `setup()` for requests that need longer to complete. The value is forwarded to
`paj bridge request --timeout`.

## Development

```sh
stylua --check lua plugin tests
nvim --headless -u NONE -l tests/headless.lua
```
