# Explanation of Lua Code

This document provides an extensive explanation of the Lua code, detailing its functionality, structure, and working mechanism. The script is designed as a Kong plugin that processes request and response bodies, applies transformations based on custom patterns, and updates the log serializer with structured data.

## Overview

This script is a Kong plugin that:

- Extends the functionality of Kong plugins by updating the log serializer.
- Supports gzip-inflated responses.
- Applies transformations to the body using configurable Lua expressions.
- Serializes and updates structured data for analytics and debugging.

The plugin is defined in the `Handler` table with multiple Kong lifecycle functions:

- `rewrite`
- `access`
- `body_filter`
- `log`

## Dependencies

The script requires the following Lua modules:

- `kong.tools.gzip`: Provides `inflate_gzip` for decompressing gzipped responses.
- `cjson`: Used for JSON encoding and decoding.
- `kong.tools.sandbox`: Allows safe execution of custom Lua expressions.

---

# Breakdown of the Code

## 1. `log_body` Function

```lua
local function log_body(key, body, is_gzip, is_response)
```

- This function processes request or response bodies.
- If the body is gzipped, it inflates the content.
- If `is_response` is `true`, it attempts to decode JSON content.
- The processed body is stored in `kong.ctx.plugin[key]`.

## 2. `split_pattern` Function

```lua
local function split_pattern(pattern)
```

- Splits a dot-separated string (like `teams.*.members.*.name`) into a table of keys.
- Used to navigate and modify nested tables.

## 3. `set_value_with_pattern` Function

```lua
local function set_value_with_pattern(data, pattern_keys, index, set_value)
```

- Recursively traverses a nested table and updates values based on a key pattern.
- Supports wildcard (`*`) matching to apply changes to multiple elements.

Example:

```lua
local data = { users = { { name = "Alice" }, { name = "Bob" } } }
set_value_with_pattern(data, { "users", "*", "name" }, 1, "MASKED")
```

Result:

```lua
{ users = { { name = "MASKED" }, { name = "MASKED" } } }
```

## 4. `set_property_by_pattern`

```lua
local function set_property_by_pattern(data, pattern, set_value)
```

- Wrapper function to initiate the recursive transformation based on pattern matching.

---

# Kong Lifecycle Hooks

## `rewrite`

```lua
function Handler:rewrite(conf)
```

- Runs at the rewrite phase.
- Enables request body buffering.
- Stores the pre-modified request body.

## `access`

```lua
function Handler:access(conf)
```

- Ensures request body buffering is enabled.
- Processes the request body for logging purposes.

## `body_filter`

```lua
function Handler:body_filter(conf)
```

- Runs when Kong is processing the response.
- Handles gzip-inflated responses.

## `log`

```lua
function Handler:log(conf)
```

- Runs at the logging phase.
- Serializes request and response data.
- Uses `sandbox(expression)()` to evaluate custom transformations.
- Updates Kong's log serializer with processed values.

---

# What is `kong.ctx`?

`kong.ctx` is a shared context object in Kong that persists data across different phases of the request lifecycle. It is used for storing and passing data between different Kong plugin phases within a single request.

- `kong.ctx.plugin`: A table that is specific to the current plugin and allows storing plugin-related data.
- `kong.ctx.shared`: A shared table that can be used across different plugins and phases.

For more details, refer to the official Kong PDK documentation.

[Kong PDK Documentation](https://docs.konghq.com/gateway/latest/pdk/)

---

# Example: Request Body Handling and Masking

### Example Request Body:

```json
{
  "users": [
    {
      "id": 1,
      "name": "Alice",
      "email": "alice@example.com",
      "password": "alicepass",
      "addresses": [
        { "type": "home", "details": "123 Main St" },
        { "type": "work", "details": "456 Office Rd" }
      ]
    },
    {
      "id": 2,
      "name": "Bob",
      "email": "bob@example.com",
      "password": "bobpass",
      "addresses": [
        { "type": "home", "details": "789 Home Ln" }
      ]
    }
  ]
}
```

### Example Masking Pattern:

```lua
set_property_by_pattern(data, "users.*.password", "MASKED")
set_property_by_pattern(data, "users.*.email", "MASKED")
set_property_by_pattern(data, "users.*.addresses.*.details", "REDACTED")
```

### Resulting Logged Data:

```json
{
  "users": [
    {
      "id": 1,
      "name": "Alice",
      "email": "MASKED",
      "password": "MASKED",
      "addresses": [
        { "type": "home", "details": "REDACTED" },
        { "type": "work", "details": "REDACTED" }
      ]
    },
    {
      "id": 2,
      "name": "Bob",
      "email": "MASKED",
      "password": "MASKED",
      "addresses": [
        { "type": "home", "details": "REDACTED" }
      ]
    }
  ]
}
```

This ensures that sensitive information is replaced before logging.

---

# Summary

- The plugin extends Kong's logging functionality by updating the log serializer.
- It supports gzip decompression.
- Patterns (`teams.*.members.*.name`) can be used to transform data dynamically.
- Updates structured data for debugging and analytics.
- Sensitive fields can be masked using custom transformation rules.

