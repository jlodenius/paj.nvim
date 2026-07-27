local client = require("paj.client")
local context = require("paj.context")

local M = {}

local defaults = {
  command = "paj",
  timeout = 300,
  output_height = 14,
  max_prompt_bytes = 200 * 1024,
}

local config = vim.deepcopy(defaults)
local selected_sessions = {}
local configured = false

local function project_root()
  return vim.fs.root(0, ".git") or vim.uv.cwd()
end

local function session_label(session)
  local branch = session.branch or "no branch"
  local task = session.task and (" — " .. session.task) or ""
  return string.format("%s [%s/%s] %s%s", session.name, session.role, session.status, branch, task)
end

local function choose_session(cwd, sessions, callback)
  if #sessions == 0 then
    vim.notify("No live Paj sessions found for this project", vim.log.levels.WARN)
    return
  end
  if #sessions == 1 then
    selected_sessions[cwd] = sessions[1].id
    callback(sessions[1])
    return
  end
  vim.ui.select(sessions, {
    prompt = "Paj session",
    format_item = session_label,
  }, function(session)
    if not session then
      return
    end
    selected_sessions[cwd] = session.id
    callback(session)
  end)
end

local function resolve_session(cwd, force_picker, callback)
  client.list_sessions(config, cwd, function(sessions, err)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end
    local bridged = vim.tbl_filter(function(session)
      return session.bridgeSocket ~= nil
    end, sessions)
    local selected = selected_sessions[cwd]
    if selected and not force_picker then
      for _, session in ipairs(bridged) do
        if session.id == selected then
          callback(session)
          return
        end
      end
    end
    choose_session(cwd, bridged, callback)
  end)
end

local function set_buffer_lines(buffer, lines)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
end

local function append_text(buffer, text)
  if text == "" or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.bo[buffer].modifiable = true
  local row = vim.api.nvim_buf_line_count(buffer) - 1
  local line = vim.api.nvim_buf_get_lines(buffer, row, row + 1, false)[1] or ""
  vim.api.nvim_buf_set_text(buffer, row, #line, row, #line, vim.split(text, "\n", { plain = true }))
  vim.bo[buffer].modifiable = false
end

local function open_output(session)
  vim.cmd(string.format("botright %dnew", config.output_height))
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buffer, string.format("paj://%s/%d", session.name, vim.uv.hrtime()))
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "markdown"
  set_buffer_lines(buffer, { "# Paj · " .. session.name .. " · connecting", "", "" })
  return buffer
end

local function set_header(buffer, session, status)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { string.format("# Paj · %s · %s", session.name, status) })
  vim.bo[buffer].modifiable = false
end

local function run_prompt(text)
  if text == "" then
    return
  end
  if #text > config.max_prompt_bytes then
    vim.notify(string.format("Paj prompt exceeds %d bytes", config.max_prompt_bytes), vim.log.levels.ERROR)
    return
  end
  local cwd = project_root()
  resolve_session(cwd, false, function(session)
    local buffer = open_output(session)
    client.prompt(config, cwd, session, text, {
      on_event = function(event)
        if event.event == "accepted" then
          set_header(buffer, session, "working")
        elseif event.event == "delta" then
          append_text(buffer, event.text or "")
        elseif event.event == "complete" then
          local body = vim.split(event.text or "", "\n", { plain = true })
          set_buffer_lines(buffer, vim.list_extend({ "# Paj · " .. session.name .. " · complete", "" }, body))
        elseif event.event == "error" then
          set_header(buffer, session, "error")
          append_text(buffer, string.format("\n%s: %s", event.code or "error", event.message or "Unknown bridge error"))
        end
      end,
      on_error = function(message)
        vim.schedule(function()
          set_header(buffer, session, "error")
          append_text(buffer, "\n" .. message)
          vim.notify(message, vim.log.levels.ERROR)
        end)
      end,
    })
  end)
end

local function prompt_command(command)
  if command.args ~= "" then
    run_prompt(command.args)
    return
  end
  vim.ui.input({ prompt = "Paj prompt: " }, function(input)
    if input then
      run_prompt(input)
    end
  end)
end

function M.setup(options)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  if configured then
    return
  end
  configured = true

  vim.api.nvim_create_user_command("PajSessions", function()
    local cwd = project_root()
    resolve_session(cwd, true, function(session)
      vim.notify("Paj attached to " .. session.name, vim.log.levels.INFO)
    end)
  end, {})
  vim.api.nvim_create_user_command("PajAttach", function()
    local cwd = project_root()
    resolve_session(cwd, true, function(session)
      vim.notify("Paj attached to " .. session.name, vim.log.levels.INFO)
    end)
  end, {})
  vim.api.nvim_create_user_command("PajPrompt", prompt_command, { nargs = "*" })
  vim.api.nvim_create_user_command("PajExplain", function(command)
    run_prompt(context.explain(command))
  end, {
    nargs = "*",
    range = true,
  })
  vim.api.nvim_create_user_command("PajReview", function(command)
    run_prompt(context.review(command))
  end, {
    nargs = "*",
    range = true,
  })
end

return M
