local typedefs = require "kong.db.schema.typedefs"


return {
  name = "log-extend",
  fields = {
    { protocols = typedefs.protocols },
    { consumer = typedefs.no_consumer },
    { service = typedefs.no_service },
    { route = typedefs.no_route },
    {
      config = {
        type = "record",
        fields = {
          { request_body = { description = "Include the request body in the logs.", type = "boolean", required = true, default = true } },
          { request_body_pre = { description = "Include the request body before transformations in the logs.", type = "boolean", required = true, default = false } },
          { response_body = { description = "Include the response body in the logs.", type = "boolean", required = true, default = true } },
          { response_body_pre = { description = "Include the response body before transformations in the logs.", type = "boolean", required = true, default = false } },
          { extend_on_error = { description = "Extend the logs only if the response status code is >= 400.", type = "boolean", required = true, default = false } },
          { custom_fields_by_lua = typedefs.lua_code },
        },
      },
    },
  }
}
