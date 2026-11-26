local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local api = vim.api
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local path = tmp .. "/target.lua"
local calls = {}
vim.system = function(argv, options, callback)
  local call = { argv = argv, input = vim.json.decode(options.stdin), complete = callback }
  calls[#calls + 1] = call
  return {
    kill = function()
      call.killed = true
    end,
  }
end

local paj = require("paj")
paj.setup()
local function text()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end
local initial = { "header", "before", "local val = 1", "after", "footer", "end" }
local function open(lines)
  if api.nvim_buf_get_name(0) == path then
    vim.cmd("bwipeout!")
  end
  vim.fn.writefile(lines or initial, path)
  vim.cmd.edit(path)
end
local function complete(replacement)
  local message = {
    role = "assistant",
    stopReason = "stop",
    content = {
      { type = "text", text = vim.json.encode({ replacement = replacement }) },
    },
  }
  calls[#calls].complete({ code = 0, signal = 0, stdout = vim.json.encode({ type = "message_end", message = message }) })
end
local function wait(predicate)
  assert(vim.wait(2000, predicate, 10), "timed out waiting for edit")
end
local ns = api.nvim_get_namespaces()["paj.edit"]
local function marks()
  return api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
end

open()
vim.cmd("3PajEdit set val to two")
local first = calls[1]
assert(first.argv[1] == "pi" and vim.tbl_contains(first.argv, "--no-tools"))
assert(not vim.tbl_contains(first.argv, "--model") and not vim.tbl_contains(first.argv, "--thinking"))
assert(first.input.instruction == "set val to two" and first.input.selection == "local val = 1")
assert(marks()[1][4].hl_group == "Visual" and marks()[1][4].virt_text[1][1]:find("PajEdit", 1, true))
api.nvim_buf_set_lines(0, 0, 0, false, { "inserted above" })
api.nvim_buf_set_lines(0, -1, -1, false, { "inserted below" })
complete("local val = 2")
wait(function()
  return text()[4] == "local val = 2"
end)
assert(text()[1] == "inserted above" and text()[8] == "inserted below")
assert(vim.fn.readfile(path)[3] == "local val = 1")
vim.cmd.undo()
assert(text()[4] == "local val = 1" and text()[1] == "inserted above" and text()[8] == "inserted below")

paj.setup({ edit = { model = "provider/small", thinking = "low" } })
open()
vim.cmd("3PajEdit change this")
local last = calls[#calls]
assert(last.argv[#last.argv - 3] == "--model" and last.argv[#last.argv - 2] == "provider/small")
assert(last.argv[#last.argv - 1] == "--thinking" and last.argv[#last.argv] == "low")
vim.cmd("bdelete")
vim.cmd.edit(path)
assert(marks()[1][2] == 2 and marks()[1][4].hl_group == "Visual")
complete("changed after reopening")
wait(function()
  return text()[3] == "changed after reopening"
end)

open()
vim.cmd("3PajEdit another edit")
vim.cmd("bwipeout")
complete("completed while closed")
vim.wait(30, function()
  return false
end)
vim.fn.writefile({ "new header", unpack(initial) }, path)
vim.cmd.edit(path)
wait(function()
  return text()[4] == "completed while closed"
end)
assert(text()[1] == "new header")

open()
vim.cmd("3PajEdit conflict")
api.nvim_buf_set_lines(0, 2, 3, false, { "user version" })
complete("stale response")
wait(function()
  return #marks() == 0
end)
assert(text()[3] == "user version")

open()
vim.cmd("3PajEdit ambiguous")
vim.cmd("bwipeout")
vim.fn.writefile(vim.list_extend(vim.deepcopy(initial), initial), path)
vim.cmd.edit(path)
assert(calls[#calls].killed and #marks() == 0 and text()[3] == initial[3])

open({ "left é right" })
local source = api.nvim_get_current_buf()
local before_draft = #calls
vim.cmd.PajEdit()
local draft = api.nvim_get_current_buf()
assert(draft ~= source and vim.bo[draft].buftype == "acwrite")
assert(api.nvim_win_get_config(0).relative == "editor" and #calls == before_draft)
vim.cmd.write()
assert(api.nvim_get_current_buf() == draft and #calls == before_draft)
for _, mapping in ipairs(api.nvim_buf_get_keymap(draft, "n")) do
  if mapping.lhs == "q" then
    mapping.callback()
    break
  end
end
assert(api.nvim_get_current_buf() == source and #calls == before_draft and #marks() == 0)

vim.keymap.set("x", "ge", "<Plug>(PajEdit)")
vim.cmd("normal! 0fév")
api.nvim_feedkeys("ge", "mx", false)
assert(vim.bo.buftype == "acwrite" and #calls == before_draft)
api.nvim_buf_set_lines(0, 0, -1, false, { "replace only the selection", "keep the surrounding text" })
vim.cmd.write()
assert(api.nvim_get_current_buf() == source and #calls == before_draft + 1)
assert(calls[#calls].input.selection == "é", vim.inspect(calls[#calls].input))
assert(calls[#calls].input.instruction == "replace only the selection\nkeep the surrounding text")
complete("Ω")
wait(function()
  return text()[1] == "left Ω right"
end)

vim.cmd("PajEdit bad output")
local malformed = {
  role = "assistant",
  stopReason = "stop",
  content = {
    { type = "text", text = "Here is a replacement, but not valid JSON." },
  },
}
calls[#calls].complete({ code = 0, signal = 0, stdout = vim.json.encode({ type = "message_end", message = malformed }) })
wait(function()
  return #marks() == 0
end)
assert(text()[1] == "left Ω right")

vim.cmd("PajEdit cancel me")
vim.cmd.PajEditCancel()
assert(calls[#calls].killed and #marks() == 0)
complete("late output")
vim.wait(30, function()
  return false
end)
assert(text()[1] == "left Ω right")
vim.fn.delete(tmp, "rf")
print("PajEdit headless tests passed")
