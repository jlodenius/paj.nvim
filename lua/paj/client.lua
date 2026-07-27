local protocol = require("paj.protocol")

local M = {}

local function executable(config)
  if vim.fn.executable(config.command) ~= 1 then
    return nil, string.format("Paj executable not found: %s", config.command)
  end
  return config.command
end

function M.list_sessions(config, cwd, callback)
  local command, err = executable(config)
  if not command then
    callback(nil, err)
    return
  end
  vim.system({ command, "--json", "session", "list" }, { cwd = cwd, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, vim.trim(result.stderr or "paj session list failed"))
        return
      end
      local ok, sessions = pcall(vim.json.decode, result.stdout)
      if not ok or type(sessions) ~= "table" then
        callback(nil, "Paj returned invalid session data")
        return
      end
      callback(sessions)
    end)
  end)
end

function M.prompt(config, cwd, session, text, handlers)
  local command, err = executable(config)
  if not command then
    handlers.on_error(err)
    return
  end
  local prompt_file = vim.fn.tempname()
  local descriptor, open_error = vim.uv.fs_open(prompt_file, "w", 384)
  if not descriptor then
    handlers.on_error("Failed to create Paj prompt: " .. tostring(open_error))
    return
  end
  local written, write_error = vim.uv.fs_write(descriptor, text, -1)
  vim.uv.fs_close(descriptor)
  if written ~= #text then
    vim.fn.delete(prompt_file)
    handlers.on_error("Failed to write Paj prompt: " .. tostring(write_error or "incomplete write"))
    return
  end

  local stderr = {}
  local saw_protocol_error = false
  local decoder = protocol.decoder(function(event)
    if event.event == "error" then
      saw_protocol_error = true
    end
    handlers.on_event(event)
  end, function(message)
    saw_protocol_error = true
    handlers.on_error(message)
  end)
  local job = vim.fn.jobstart({
    command,
    "--json",
    "bridge",
    "prompt",
    session.id,
    "--prompt-file",
    prompt_file,
    "--timeout",
    tostring(config.timeout),
  }, {
    cwd = cwd,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      decoder.feed(data)
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then
          table.insert(stderr, line)
        end
      end
    end,
    on_exit = function(_, code)
      decoder.finish()
      vim.fn.delete(prompt_file)
      vim.schedule(function()
        if code ~= 0 and not saw_protocol_error then
          handlers.on_error(
            #stderr > 0 and table.concat(stderr, "\n") or string.format("Paj exited with status %d", code)
          )
        end
        if handlers.on_exit then
          handlers.on_exit(code)
        end
      end)
    end,
  })
  if job <= 0 then
    vim.fn.delete(prompt_file)
    handlers.on_error("Failed to start Paj bridge client")
    return
  end
  return job
end

return M
