local M = {}

local function source(first_line, last_line)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    path = "[No Name]"
  end
  local lines = vim.api.nvim_buf_get_lines(0, first_line - 1, last_line, false)
  return table.concat({
    string.format('<source path="%s" lines="%d-%d">', path, first_line, last_line),
    table.concat(lines, "\n"),
    "</source>",
  }, "\n")
end

function M.explain(command)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local first_line = command.range > 0 and command.line1 or line
  local last_line = command.range > 0 and command.line2 or line
  local instruction = "Explain this code clearly, including any non-obvious behavior or risks."
  if command.args ~= "" then
    instruction = instruction .. " Focus on: " .. command.args
  end
  return instruction .. "\n\n" .. source(first_line, last_line)
end

function M.review(command)
  local first_line = command.range > 0 and command.line1 or 1
  local last_line = command.range > 0 and command.line2 or vim.api.nvim_buf_line_count(0)
  local instruction =
    "Review this code for concrete correctness, maintainability, and security issues. Prioritize findings by severity."
  if command.args ~= "" then
    instruction = instruction .. " Focus on: " .. command.args
  end
  return instruction .. "\n\n" .. source(first_line, last_line)
end

return M
