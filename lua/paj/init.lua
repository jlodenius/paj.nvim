local client = require("paj.client")
local context = require("paj.context")
local response = require("paj.response")

local M = {}

---@alias PajOutputPosition "top" | "bottom" | "left" | "right"

---@class PajConfig
---@field command? string Paj executable name or path
---@field timeout? number Bridge request timeout in seconds
---@field output_size? number Output split size as a percentage from 1 to 100
---@field output_position? PajOutputPosition Output split position
---@field max_prompt_bytes? number Maximum request content size in bytes

local defaults = {
  command = "paj",
  timeout = 300,
  output_size = 30,
  output_position = "bottom",
  max_prompt_bytes = 200 * 1024,
}

local config = vim.deepcopy(defaults)
local selected_sessions = {}
local requests = {}
local configured = false
local footer_namespace = vim.api.nvim_create_namespace("paj.response.footer")
local open_text_input
local render_response_actions
local run_prompt

local function project_root()
  return vim.fs.root(0, ".git") or vim.uv.cwd()
end

local function session_label(session)
  local branch = type(session.branch) == "string" and session.branch or "no branch"
  local task = type(session.task) == "string" and (" — " .. session.task) or ""
  return string.format("%s [%s] %s%s", session.name, session.role, branch, task)
end

local function choose_session(cwd, sessions, remember, callback)
  if #sessions == 0 then
    vim.notify("No live Paj sessions found for this project", vim.log.levels.WARN)
    return
  end
  if #sessions == 1 then
    if remember then
      selected_sessions[cwd] = sessions[1].id
    end
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
    if remember then
      selected_sessions[cwd] = session.id
    end
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
    if force_picker then
      choose_session(cwd, bridged, true, callback)
      return
    end

    local selected = selected_sessions[cwd]
    if selected then
      for _, session in ipairs(bridged) do
        if session.id == selected then
          callback(session)
          return
        end
      end
      selected_sessions[cwd] = nil
    end

    local primaries = vim.tbl_filter(function(session)
      return session.role == "primary"
    end, bridged)
    choose_session(cwd, #primaries > 0 and primaries or bridged, false, callback)
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

local function set_header(buffer, session, status)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { string.format("# Paj · %s · %s", session.name, status) })
  vim.bo[buffer].modifiable = false
end

local function cancel_request(buffer, update_status)
  local request = requests[buffer]
  if not request or not request.active then
    return false
  end
  request.active = false
  request.cancelled = true
  if request.job then
    vim.fn.jobstop(request.job)
  end
  if update_status ~= false then
    set_header(buffer, request.session, "cancelled")
    render_response_actions(buffer)
  end
  return true
end

local function close_output(buffer)
  cancel_request(buffer)
  if vim.api.nvim_buf_is_valid(buffer) then
    vim.api.nvim_buf_delete(buffer, { force = true })
  end
end

local function pending_actions(request)
  return vim.tbl_filter(function(action)
    return action.status == "pending"
  end, request.actions or {})
end

local function truncate_display(text, width)
  if width <= 0 then
    return ""
  end
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local length = vim.fn.strchars(text)
  while length > 0 do
    local candidate = vim.fn.strcharpart(text, 0, length) .. "…"
    if vim.fn.strdisplaywidth(candidate) <= width then
      return candidate
    end
    length = length - 1
  end
  return ""
end

local function update_footer_layout(request)
  if
    not request
    or not request.window
    or not vim.api.nvim_win_is_valid(request.window)
    or not request.footer_window
    or not vim.api.nvim_win_is_valid(request.footer_window)
  then
    return
  end
  local width = math.max(1, vim.api.nvim_win_get_width(request.window))
  local row = math.max(0, vim.api.nvim_win_get_height(request.window) - 1)
  local current = vim.api.nvim_win_get_config(request.footer_window)
  if current.width ~= width or current.row ~= row then
    vim.api.nvim_win_set_config(request.footer_window, {
      relative = "win",
      win = request.window,
      row = row,
      col = 0,
      width = width,
      height = 1,
    })
  end
end

local function footer_line(request, width)
  local left = ""
  local controls
  if request.active then
    left = " Paj is working…"
    controls = "[q] Cancel "
  elseif request.cancelled then
    left = " Paj request cancelled"
    controls = "[q] Close "
  else
    local pending = pending_actions(request)
    if #pending == 1 then
      controls = "[a] Accept   [f] Follow up   [q] Close "
    elseif #pending > 1 then
      left = string.format(" %d suggested changes", #pending)
      controls = "[a] Choose and accept   [f] Follow up   [q] Close "
    else
      controls = "[f] Follow up   [q] Close "
    end
  end

  if vim.fn.strdisplaywidth(controls) >= width then
    return truncate_display(controls, width)
  end
  local available = width - vim.fn.strdisplaywidth(controls)
  left = truncate_display(left, math.max(0, available - 1))
  local padding = string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(controls)))
  return left .. padding .. controls
end

render_response_actions = function(buffer)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return
  end
  local request = requests[buffer]
  if
    not request
    or not request.footer_buffer
    or not vim.api.nvim_buf_is_valid(request.footer_buffer)
    or not request.footer_window
    or not vim.api.nvim_win_is_valid(request.footer_window)
  then
    return
  end

  update_footer_layout(request)
  local width = vim.api.nvim_win_get_width(request.footer_window)
  local line = footer_line(request, width)
  vim.bo[request.footer_buffer].modifiable = true
  vim.api.nvim_buf_set_lines(request.footer_buffer, 0, -1, false, { line })
  vim.api.nvim_buf_clear_namespace(request.footer_buffer, footer_namespace, 0, -1)
  for _, key in ipairs({ "[a]", "[f]", "[q]" }) do
    local start = line:find(key, 1, true)
    if start then
      vim.api.nvim_buf_set_extmark(request.footer_buffer, footer_namespace, 0, start - 1, {
        end_col = start - 1 + #key,
        hl_group = "WarningMsg",
      })
    end
  end
  vim.bo[request.footer_buffer].modifiable = false
end

local function create_output_footer(buffer, window)
  local request = requests[buffer]
  request.window = window
  request.footer_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(request.footer_buffer, string.format("paj-footer://%d", vim.uv.hrtime()))
  vim.bo[request.footer_buffer].buftype = "nofile"
  vim.bo[request.footer_buffer].bufhidden = "wipe"
  vim.bo[request.footer_buffer].swapfile = false
  vim.wo[window].scrolloff = math.max(vim.wo[window].scrolloff, 1)
  request.footer_window = vim.api.nvim_open_win(request.footer_buffer, false, {
    relative = "win",
    win = window,
    row = math.max(0, vim.api.nvim_win_get_height(window) - 1),
    col = 0,
    width = math.max(1, vim.api.nvim_win_get_width(window)),
    height = 1,
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 200,
  })
  vim.wo[request.footer_window].winhl = "Normal:StatusLine"

  request.group = vim.api.nvim_create_augroup("paj_output_" .. buffer, { clear = true })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = request.group,
    callback = function()
      update_footer_layout(requests[buffer])
      render_response_actions(buffer)
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = request.group,
    buffer = buffer,
    callback = function()
      update_footer_layout(requests[buffer])
      render_response_actions(buffer)
    end,
  })
  render_response_actions(buffer)
end

local function follow_up_response(buffer)
  local request = requests[buffer]
  if not request or request.active then
    vim.notify("Wait for the Paj response to complete", vim.log.levels.INFO)
    return
  end
  open_text_input({ title = " Paj follow-up " }, function(question)
    run_prompt(response.followup_prompt(question), request.cwd, request.session, buffer, {
      kind = "followup",
      text = question,
    })
  end)
end

local function accept_response(buffer)
  local request = requests[buffer]
  if not request or request.active then
    vim.notify("Wait for the Paj response to complete", vim.log.levels.INFO)
    return
  end
  local pending = pending_actions(request)
  if #pending == 0 then
    vim.notify("This response has no pending proposed changes", vim.log.levels.INFO)
    return
  end

  local function accept(action)
    if not action then
      return
    end
    action.status = "accepted"
    render_response_actions(buffer)
    run_prompt(response.accept_prompt(action), request.cwd, request.session, buffer, {
      kind = "accepted",
      text = action.title,
    })
  end

  if #pending == 1 then
    accept(pending[1])
    return
  end
  vim.ui.select(pending, {
    prompt = "Accept proposed change",
    format_item = function(action)
      return action.title
    end,
  }, accept)
end

local function output_split_size(position)
  if (position == "top" or position == "bottom") and type(config.output_height) == "number" then
    return math.max(1, math.floor(config.output_height))
  end
  local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
  local dimension = (position == "left" or position == "right") and ui.width or ui.height
  return math.max(1, math.floor(dimension * config.output_size / 100))
end

local function open_output(session, cwd)
  local position = config.output_position
  local modifier = (position == "top" or position == "left") and "topleft" or "botright"
  local vertical = position == "left" or position == "right"
  local command = string.format("%s %s%dnew", modifier, vertical and "vertical " or "", output_split_size(position))
  vim.cmd(command)
  local window = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buffer, string.format("paj://%s/%d", session.name, vim.uv.hrtime()))
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "markdown"
  requests[buffer] = { active = true, cancelled = false, session = session, cwd = cwd, actions = {} }
  vim.api.nvim_buf_create_user_command(buffer, "PajCancel", function()
    if not cancel_request(buffer) then
      vim.notify("No active Paj request in this buffer", vim.log.levels.INFO)
    end
  end, {})
  vim.api.nvim_buf_create_user_command(buffer, "PajClose", function()
    close_output(buffer)
  end, {})
  vim.api.nvim_buf_create_user_command(buffer, "PajAccept", function()
    accept_response(buffer)
  end, {})
  vim.api.nvim_buf_create_user_command(buffer, "PajFollowUp", function()
    follow_up_response(buffer)
  end, {})
  vim.keymap.set("n", "a", function()
    accept_response(buffer)
  end, { buffer = buffer, silent = true, desc = "Accept a Paj proposed change" })
  vim.keymap.set("n", "f", function()
    follow_up_response(buffer)
  end, { buffer = buffer, silent = true, desc = "Follow up on the Paj response" })
  vim.keymap.set("n", "q", function()
    if not cancel_request(buffer) then
      close_output(buffer)
    end
  end, { buffer = buffer, silent = true, desc = "Cancel or close Paj output" })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      cancel_request(buffer, false)
      local request = requests[buffer]
      if request and request.footer_window and vim.api.nvim_win_is_valid(request.footer_window) then
        vim.api.nvim_win_close(request.footer_window, true)
      end
      if request and request.footer_buffer and vim.api.nvim_buf_is_valid(request.footer_buffer) then
        vim.api.nvim_buf_delete(request.footer_buffer, { force = true })
      end
      if request and request.group then
        pcall(vim.api.nvim_del_augroup_by_id, request.group)
      end
      requests[buffer] = nil
    end,
  })
  set_buffer_lines(buffer, { "# Paj · " .. session.name .. " · connecting", "", "" })
  create_output_footer(buffer, window)
  return buffer
end

local function append_turn(buffer, entry)
  if not entry then
    return
  end
  local lines = { "", "---", "" }
  if entry.kind == "followup" then
    vim.list_extend(lines, { "## You", "" })
    vim.list_extend(lines, vim.split(entry.text, "\n", { plain = true }))
    vim.list_extend(lines, { "", "## Agent", "", "" })
  else
    vim.list_extend(lines, { "## Accepted · " .. entry.text, "", "## Agent", "", "" })
  end
  vim.bo[buffer].modifiable = true
  vim.api.nvim_buf_set_lines(buffer, -1, -1, false, lines)
  vim.bo[buffer].modifiable = false
end

local function show_latest_turn(buffer, response_start)
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(window) == buffer then
      vim.api.nvim_win_set_cursor(window, { math.max(1, response_start - 1), 0 })
      vim.api.nvim_win_call(window, function()
        vim.cmd("normal! zt")
      end)
    end
  end
end

local function merge_actions(existing, added)
  local ids = {}
  for _, action in ipairs(existing) do
    ids[action.id] = true
  end
  for _, action in ipairs(added) do
    if not ids[action.id] then
      ids[action.id] = true
      table.insert(existing, action)
    end
  end
  return existing
end

run_prompt = function(text, cwd, target_session, target_buffer, entry)
  if text == "" then
    return
  end
  if #text > config.max_prompt_bytes then
    vim.notify(string.format("Paj prompt exceeds %d bytes", config.max_prompt_bytes), vim.log.levels.ERROR)
    return
  end
  cwd = cwd or project_root()
  local prompt = text

  local function start(session)
    local continuing = target_buffer and vim.api.nvim_buf_is_valid(target_buffer)
    if target_buffer and not continuing then
      vim.notify("The Paj response buffer is no longer available", vim.log.levels.ERROR)
      return
    end
    local buffer = continuing and target_buffer or open_output(session, cwd)
    local request = requests[buffer]
    request.active = true
    request.cancelled = false
    request.generation = (request.generation or 0) + 1
    local generation = request.generation
    render_response_actions(buffer)
    append_turn(buffer, entry)
    request.response_start = vim.api.nvim_buf_line_count(buffer) - 1
    if continuing then
      show_latest_turn(buffer, request.response_start)
    end
    set_header(buffer, session, "connecting")

    request.job = client.prompt(config, cwd, session, prompt, {
      on_event = function(event)
        if request.cancelled or request.generation ~= generation then
          return
        end
        if event.event == "accepted" then
          set_header(buffer, session, "working")
        elseif event.event == "delta" then
          append_text(buffer, event.text or "")
        elseif event.event == "complete" then
          request.active = false
          request.response = type(event.text) == "string" and event.text or ""
          local actions = response.validate_actions(event.actions)
          request.actions = continuing and merge_actions(request.actions, actions) or actions
          local body = vim.split(request.response, "\n", { plain = true })
          vim.bo[buffer].modifiable = true
          vim.api.nvim_buf_set_lines(buffer, request.response_start, -1, false, body)
          vim.bo[buffer].modifiable = false
          set_header(buffer, session, "complete")
          render_response_actions(buffer)
        elseif event.event == "error" then
          request.active = false
          set_header(buffer, session, "error")
          append_text(buffer, string.format("\n%s: %s", event.code or "error", event.message or "Unknown bridge error"))
          render_response_actions(buffer)
        end
      end,
      on_error = function(message)
        vim.schedule(function()
          if request.cancelled or request.generation ~= generation then
            return
          end
          request.active = false
          set_header(buffer, session, "error")
          append_text(buffer, "\n" .. message)
          render_response_actions(buffer)
          vim.notify(message, vim.log.levels.ERROR)
        end)
      end,
      on_exit = function()
        if request.generation == generation then
          request.job = nil
        end
      end,
    })
    if not request.job and not request.cancelled then
      request.active = false
    end
  end

  if target_session then
    start(target_session)
  else
    resolve_session(cwd, false, start)
  end
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

local function create_query_footer(row, col, width)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buffer, string.format("paj-query-footer://%d", vim.uv.hrtime()))
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { " :w=submit q=cancel" })

  local namespace = vim.api.nvim_create_namespace("paj.query.footer")
  vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 1, { end_col = 3, hl_group = "WarningMsg" })
  vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 4, { end_col = 10, hl_group = "Comment" })
  vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 11, { end_col = 12, hl_group = "WarningMsg" })
  vim.api.nvim_buf_set_extmark(buffer, namespace, 0, 13, { end_col = 19, hl_group = "Comment" })
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].readonly = true

  local window = vim.api.nvim_open_win(buffer, false, {
    relative = "editor",
    row = row,
    col = col + 1,
    width = width - 2,
    height = 1,
    style = "minimal",
    zindex = 200,
    focusable = false,
  })
  return buffer, window
end

open_text_input = function(options, on_submit)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buffer, string.format("paj-query://%d", vim.uv.hrtime()))
  vim.bo[buffer].buftype = "acwrite"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "markdown"

  local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
  local width = math.max(3, math.floor(ui.width * 2 / 3))
  local height = math.max(1, math.floor(ui.height / 3))
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = options.title,
    title_pos = "center",
    zindex = 100,
  })
  vim.wo[window].wrap = true
  local footer_buffer, footer_window = create_query_footer(row + height, col, width)

  local closed = false
  local group = vim.api.nvim_create_augroup("paj_query_" .. buffer, { clear = true })
  local function close_input()
    if closed then
      return
    end
    closed = true
    if vim.api.nvim_win_is_valid(footer_window) then
      vim.api.nvim_win_close(footer_window, true)
    end
    if vim.api.nvim_buf_is_valid(footer_buffer) then
      vim.api.nvim_buf_delete(footer_buffer, { force = true })
    end
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end

  local sent = false
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buffer,
    callback = function()
      if sent then
        return
      end
      local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n"))
      if text == "" then
        vim.notify(options.empty_message or "Paj input cannot be empty", vim.log.levels.WARN)
        return
      end
      sent = true
      vim.bo[buffer].modified = false
      close_input()
      on_submit(text)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(window),
    callback = close_input,
  })
  vim.keymap.set("n", "q", close_input, { buffer = buffer, silent = true, nowait = true, desc = "Cancel Paj input" })
  vim.cmd("startinsert")
end

local function open_query(command)
  local captured_source = context.capture(command)
  local cwd = project_root()
  open_text_input({ title = " Paj query ", empty_message = "Paj query cannot be empty" }, function(query)
    run_prompt(context.query(captured_source, query), cwd)
  end)
end

local function validate_config(candidate)
  if
    type(candidate.output_size) ~= "number"
    or candidate.output_size ~= candidate.output_size
    or candidate.output_size < 1
    or candidate.output_size > 100
  then
    error("paj.nvim: output_size must be a number from 1 to 100")
  end
  if not vim.tbl_contains({ "top", "bottom", "left", "right" }, candidate.output_position) then
    error("paj.nvim: output_position must be one of: top, bottom, left, right")
  end
  if
    candidate.output_height ~= nil
    and (
      type(candidate.output_height) ~= "number"
      or candidate.output_height ~= candidate.output_height
      or candidate.output_height < 1
      or candidate.output_height >= math.huge
    )
  then
    error("paj.nvim: output_height must be a positive number")
  end
end

---@param options? PajConfig
function M.setup(options)
  local candidate = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  validate_config(candidate)
  config = candidate
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
  vim.api.nvim_create_user_command("PajQuery", open_query, { range = true })
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
