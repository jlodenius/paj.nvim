local M = {}

local function source(command)
  local first_line = command.range > 0 and command.line1 or 1
  local last_line = command.range > 0 and command.line2 or vim.api.nvim_buf_line_count(0)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    path = "[No Name]"
  end
  local lines = vim.api.nvim_buf_get_lines(0, first_line - 1, last_line, false)
  return {
    path = path,
    startLine = first_line,
    endLine = last_line,
    content = table.concat(lines, "\n"),
  }
end

function M.capture(command)
  return source(command)
end

function M.query(captured_source, query)
  return {
    kind = "query",
    query = query,
    source = captured_source,
  }
end

function M.explain(command)
  return {
    kind = "explain",
    focus = command.args ~= "" and command.args or nil,
    source = source(command),
  }
end

function M.review(command)
  return {
    kind = "review",
    focus = command.args ~= "" and command.args or nil,
    source = source(command),
  }
end

return M
