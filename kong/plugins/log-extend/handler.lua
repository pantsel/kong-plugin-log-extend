local inflate_gzip = require("kong.tools.gzip").inflate_gzip
local cjson = require "cjson"
local sandbox = require "kong.tools.sandbox".sandbox

local kong = kong

local Handler = {
  PRIORITY = 15,
  VERSION = "0.1.0",
}

--- Strips specific prefixes from a given string.
--
-- This function checks if the input string starts with any of the predefined
-- patterns ("request.body_pre", "request.body", "response.body_pre", "response.body").
-- If a match is found, it returns true along with the matched prefix and the string
-- with the prefix stripped. If no match is found, it returns false and the original string.
--
-- @param str The input string to be processed.
-- @return boolean True if a prefix was matched and stripped, false otherwise.
-- @return string The matched prefix if a match was found, nil otherwise.
-- @return string The input string with the prefix stripped if a match was found, or the original string if no match was found.
--
-- @usage
-- local success, matched, stripped = strip_prefix("request.body_pre.data")
-- -- success == true
-- -- matched == "request.body_pre"
-- -- stripped == "data"
--
-- local success, matched, stripped = strip_prefix("response.body.content")
-- -- success == true
-- -- matched == "response.body"
-- -- stripped == "content"
--
-- local success, matched, stripped = strip_prefix("other.prefix.data")
-- -- success == false
-- -- matched == nil
-- -- stripped == "other.prefix.data"
local function strip_prefix(str)
  local patterns = {
    "^request%.body_pre",    -- Match only request.body_pre first
    "^request%.body",        -- Then match request.body
    "^response%.body_pre",   -- Match response.body_pre first
    "^response%.body"        -- Then match response.body
  }

  for _, pattern in ipairs(patterns) do
    local match_start, match_end = string.find(str, pattern)
    if match_start then
      local matched_str = string.sub(str, match_start, match_end)
      local stripped_str = string.gsub(str, pattern .. "%.", "", 1)
      return true, matched_str, stripped_str
    end
  end

  return false, nil, str
end


--[[
  Logs the body of a request or response, optionally inflating it if it is gzipped.

  @param key (string) The key under which to store the body in the plugin context.
  @param body (string) The body to log.
  @param is_gzip (boolean) Whether the body is gzipped.
  @param is_response (boolean) Whether the body is a response body.

  If the body is gzipped, it will be inflated before being logged. If the body is a response body,
  it will be decoded from JSON before being logged.

  Example usage:
  log_body("request_body", request_body, false, false)
  log_body("response_body", response_body, true, true)
]]
local function log_body(key, body, is_gzip, is_response)
  if not body then
    return
  end

  if is_gzip then
    local err
    body, err = inflate_gzip(body)
    if err then
      kong.log.err("failed to inflate gzipped body: ", err)
      return
    end
  end

  local decoded_body
  if is_response then
    local ok, result = pcall(cjson.decode, body)
    if ok then
      decoded_body = result
    end
  end

  kong.ctx.plugin[key] = decoded_body or body
end

-- Function to split a pattern like "teams.*.members.*.name" into table keys
-- @function split_pattern
-- @param pattern (string) The pattern string to be split into table keys.
-- @return (table) A table containing the split keys from the pattern.
-- @example
-- local keys = split_pattern("teams.*.members.*.name")
-- -- keys will be {"teams", "*", "members", "*", "name"}
local function split_pattern(pattern)
  local keys = {}
  for key in pattern:gmatch("[^%.]+") do
    keys[#keys + 1] = key
  end
  return keys
end

-- Recursive function to traverse and set values based on a pattern.
-- This function navigates through a nested table structure and replaces values
-- that match the given pattern with a specified value.
-- Example:
-- data = { teams = { { members = { { name = "Alice" }, { name = "Bob" } } } } }
-- pattern = "teams.*.members.*.name"
-- set_value = "MASKED"
-- Result: data = { teams = { { members = { { name = "MASKED" }, { name = "MASKED" } } } } }
--
-- data = { users = { { id = 1, name = "Alice" }, { id = 2, name = "Bob" } } }
-- pattern = "users.2.name"
-- set_value = "MASKED"
-- Result: data = { users = { { id = 1, name = "Alice" }, { id = 2, name = "MASKED" } } }
--
-- data = { config = { database = { password = "secret" } } }
-- pattern = "config.database.password"
-- set_value = "MASKED"
-- Result: data = { config = { database = { password = "MASKED" } } }
local function set_value_with_pattern(data, pattern_keys, index, set_value)
  -- If the data is not a table, return as we cannot traverse further
  if type(data) ~= "table" then return end

  -- If the current index exceeds the length of the pattern keys, return
  if index > #pattern_keys then return end

  -- Get the current key from the pattern keys
  local key = pattern_keys[index]
  -- Check if this is the last key in the pattern
  local is_last_key = (index == #pattern_keys)

  -- If the key is "*", it means we need to set the value to all elements in the table
  if key == "*" then
    -- Loop through all elements in the table and set the value recursively
    for i = 1, #data do
      set_value_with_pattern(data[i], pattern_keys, index + 1, set_value)
    end
  else
    -- Convert the key to a number if possible, otherwise use it as a string
    local next_key = tonumber(key) or key
    -- Get the next level of data using the current key
    local next_data = data[next_key]

    -- If the next level of data exists
    if next_data then
      -- If this is the last key and the next data is a string, set the value
      if is_last_key and type(next_data) == "string" then
        data[next_key] = set_value
      else
        -- Otherwise, continue traversing the table recursively
        set_value_with_pattern(next_data, pattern_keys, index + 1, set_value)
      end
    end
  end
end

-- Wrapper function that initiates the recursive search
local function set_property_by_pattern(data, pattern, set_value)
  local pattern_keys = split_pattern(pattern)
  set_value_with_pattern(data, pattern_keys, 1, set_value)
end

function Handler:rewrite(conf)
  if conf.request_body_pre then
    kong.service.request.enable_buffering()
    log_body("request.body_pre", kong.request.get_body(), false, false)
  end
end

function Handler:access(conf)
  if not conf.request_body then
    return
  end

  kong.service.request.enable_buffering()
  log_body("request.body", kong.request.get_body(), false, false)
end

function Handler:body_filter(conf)
  if conf.response_body then
    local is_gzip = kong.service.response.get_header("Content-Encoding") == "gzip"
    local response_body = kong.response.get_raw_body()
    if response_body then
      log_body("response.body", response_body, is_gzip, true)
    end
  end

  if conf.response_body_pre then
    local ok, service_response_body = pcall(kong.service.response.get_raw_body)
    if ok and service_response_body then
      log_body("response.body_pre", service_response_body, is_gzip, true)
    end
  end
end

function Handler:log(conf)
  local resp_status = kong.response.get_status()

  if conf.extend_on_error and resp_status < 400 then
    return
  end

  local serializable_data = kong.ctx.plugin

  -- Apply custom_fields_by_lua defined in the configuration
  if conf.custom_fields_by_lua then
    for pattern, expression in pairs(conf.custom_fields_by_lua) do
      -- Evaluate the Lua expression to get the set value
      local set_value = sandbox(expression)()
      local matched, matched_str, stripped_str = strip_prefix(pattern)
      if matched then
        -- The pattern is scoped in serializable_data
        -- example: pattern = "request.body_pre.users.*.name"
        -- matched_str = "request.body_pre"
        -- stripped_str = "users.*.name"
        set_property_by_pattern(serializable_data[matched_str], stripped_str, set_value)
      else
        -- The pattern is not scoped in serializable_data
        kong.log.set_serialize_value(pattern, set_value)
      end
    end

    -- ToDo: Decide if the simpler implementation below adds more value than the above
    -- for _, value in pairs(serializable_data) do
    --   for pattern, expression in pairs(conf.custom_fields_by_lua) do
    --     -- Evaluate the Lua expression to get the set value
    --     local set_value = sandbox(expression)()
    --     -- Set the value to the data based on the pattern
    --     set_property_by_pattern(value, pattern, set_value)
    --   end
    -- end
  end

  -- Set the serialized values to be logged
  for key, value in pairs(serializable_data) do
    kong.log.set_serialize_value(key, value)
  end
end

return Handler
