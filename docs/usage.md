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

In a reply buffer, `PajFollowUp` (`f`) asks the same Pi session a follow-up. `PajAccept` (`a`)
asks you to choose if there is more than one proposal. Closing without accepting does not
authorize edits.
