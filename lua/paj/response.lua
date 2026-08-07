local M = {}

function M.validate_actions(value)
  if type(value) ~= "table" then
    return {}
  end

  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > 20 then
      return {}
    end
    count = count + 1
  end
  if count > 20 then
    return {}
  end
  for index = 1, count do
    if value[index] == nil then
      return {}
    end
  end

  local actions = {}
  local ids = {}
  for _, action in ipairs(value) do
    if
      type(action) ~= "table"
      or type(action.id) ~= "string"
      or type(action.title) ~= "string"
      or type(action.description) ~= "string"
    then
      return {}
    end
    local id = vim.trim(action.id)
    local title = vim.trim(action.title)
    local description = vim.trim(action.description)
    if id == "" or title == "" or description == "" or #id > 100 or #title > 200 or #description > 4000 or ids[id] then
      return {}
    end
    ids[id] = true
    table.insert(actions, {
      id = id,
      title = title,
      description = description,
      status = "pending",
    })
  end
  return actions
end

function M.accept_request(action)
  return { kind = "acceptAction", actionId = action.id }
end

function M.followup_request(question)
  return { kind = "followup", question = question }
end

return M
