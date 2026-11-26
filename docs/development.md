# Troubleshooting and development

[Back to setup](../README.md).

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

Increase [`timeout` in `setup()`](settings.md#configuration) for requests that need longer to
complete. The value is forwarded to
`paj bridge request --timeout`.

## Development

```sh
stylua --check lua plugin tests
nvim --headless -u NONE -l tests/headless.lua
nvim --headless -u NONE -l tests/edit.lua
```
