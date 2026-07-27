local M = {}

function M.decoder(on_event, on_error)
  local pending = ""

  local function decode(line)
    if line == "" then
      return
    end
    local ok, event = pcall(vim.json.decode, line)
    if not ok then
      on_error("Invalid Paj bridge event: " .. line)
      return
    end
    on_event(event)
  end

  return {
    feed = function(data)
      if not data or #data == 0 then
        return
      end
      data[1] = pending .. data[1]
      for index = 1, #data - 1 do
        decode(data[index])
      end
      pending = data[#data]
    end,
    finish = function()
      decode(pending)
      pending = ""
    end,
  }
end

return M
