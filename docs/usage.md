# Editor commands and session selection

[Back to setup](../README.md).

## Session selection

The plugin prefers bridged main Pi sessions (`primary` in Paj). When exactly one primary is
available, it is selected even if subagents are also running; when multiple primaries are available,
Paj opens `vim.ui.select` for those primary sessions and remembers the choice per project while it
remains a candidate. If the topology changes to a sole primary, that session is selected instead. If
no primary is available, Paj offers all bridged sessions. Picker entries
show each session's name, role, branch, and task.

Use `:PajSessions` to explicitly choose any bridged session, including a subagent. That override is
remembered per project while Neovim is running; if the selected session disappears, normal primary
selection resumes.

## Commands and reply controls

Use `PajExplain [focus]` and `PajReview [focus]` to explain or review selected lines or the
whole buffer. `PajQuery` opens a multiline question editor; press `q` there to discard the draft.

The reply shows each attached proposal's title and description under **Proposed changes**.
`PajFollowUp` (`f`) asks the same Pi session a follow-up. `PajAccept` (`a`) asks you to choose
if there is more than one proposal. Closing without accepting does not authorize edits.

## Edit in place

Run `:PajEdit [instruction]` to edit the current line or `:[range]PajEdit [instruction]` for a range.
Omit the instruction to open the same kind of multiline draft window as `:PajQuery`. Use `:w` to
submit the draft or `q` in Normal mode to discard it. Supplying an instruction on the command line
still submits it directly. For exact characterwise or linewise visual selections, map
`<Plug>(PajEdit)` (requires Neovim's `getregionpos()`):

```lua
vim.keymap.set("x", "<leader>pe", "<Plug>(PajEdit)")
```

A highlight and spinner show the target while a fresh, tool-free Pi process works. Pi receives the
selected text, filetype, and instruction using your configured model provider; no live Paj session
is required. See [model and thinking settings](settings.md#edit-in-place).

Edits above and below the selection are preserved. If you unload and reopen the named file in the
same Neovim session, PajEdit restores the highlight and spinner or applies the finished result.
It skips the edit if the selection changed or can't be found unambiguously. A successful edit is
undoable and is not saved automatically. Run `:PajEditCancel` in the file's buffer to cancel.
