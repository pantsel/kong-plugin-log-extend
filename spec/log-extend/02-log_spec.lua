local cjson         = require "cjson"
local helpers       = require "spec.helpers"
local pl_file       = require "pl.file"
local random_string = require("kong.tools.rand").random_string
local strip         = require("kong.tools.string").strip


local PLUGIN_NAME = "log-extend"
local FILE_LOG_PATH = os.tmpname()


local function wait_for_json_log_entry()
  local json

  assert
      .with_timeout(10)
      .ignore_exceptions(true)
      .eventually(function()
        local data = assert(pl_file.read(FILE_LOG_PATH))

        data = strip(data)
        assert(#data > 0, "log file is empty")

        data = data:match("%b{}")
        assert(data, "log file does not contain JSON")

        json = cjson.decode(data)
      end)
      .has_no_error("log file contains a valid JSON entry")

  return json
end


for _, strategy in helpers.all_strategies() do
  if strategy ~= "cassandra" then
    describe("Plugin: " .. PLUGIN_NAME, function()
      local proxy_client
      local proxy_client_grpc, proxy_client_grpcs

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

        -- Global plugin
        bp.plugins:insert {
          name   = PLUGIN_NAME,
          config = {
            request_body = true,
            request_body_pre = true,
            response_body = true,
            response_body_pre = true,
            extend_on_error = false,
            custom_fields_by_lua = {
              ["request.body.organizations.1.departments.2.employees.1.email"] = "return '***'",
              ["request.body.teams.*.members.*.email"] = "return '***'",
              ["request.body_pre.users.1.email"] = "return '***'",
              ["request.body.users.*.name"] = "return '***'",
              ["request.body.some.non.existant.field"] = "return '***'",
              ["request.body.some.non.existant.field2.*"] = "return '***'",
              ["response.body.request.body.teams.1.members.1.email"] = "return '***'",
              ["source"] = "return 'kong'",
            },
          },
        }

        local route_1 = bp.routes:insert {
          hosts = { "logging.basic.test" },
        }

        bp.plugins:insert {
          route  = { id = route_1.id },
          name   = "file-log",
          config = {
            path   = FILE_LOG_PATH,
            reopen = true,
          },
        }

        local route_2 = bp.routes:insert {
          hosts = { "logging.transformed.test" },
        }

        bp.plugins:insert {
          route  = { id = route_2.id },
          name   = "file-log",
          config = {
            path   = FILE_LOG_PATH,
            reopen = true,
          },
        }

        bp.plugins:insert {
          route  = { id = route_2.id },
          name   = "request-transformer",
          config = {
            add = {
              body = {
                "foo:bar",
              },
            },
          },
        }

        bp.plugins:insert {
          route  = { id = route_2.id },
          name   = "response-transformer",
          config = {
            add = {
              json = {
                "foo_response:bar_response",
              },
            },
          },
        }



        -- start kong
        assert(helpers.start_kong({
          -- set the strategy
          database           = strategy,
          -- use the custom test template to create a local mock server
          nginx_conf         = "spec/fixtures/custom_nginx.template",
          -- make sure our plugin gets loaded
          plugins            = "bundled," .. PLUGIN_NAME,
          -- write & load declarative config, only if 'strategy=off'
          declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        }))

        proxy_client_grpc = helpers.proxy_client_grpc()
        proxy_client_grpcs = helpers.proxy_client_grpcs()
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
        os.remove(FILE_LOG_PATH)
      end)
      after_each(function()
        if proxy_client then
          proxy_client:close()
        end

        os.remove(FILE_LOG_PATH)
      end)

      it("logs request and response bodies", function()
        local uuid = random_string()

        local req_body = {
          hello = "world"
        }

        -- Making the request
        local res = proxy_client:post("/status/200", {
          headers = {
            ["file-log-uuid"] = uuid,
            ["Host"] = "logging.basic.test",
            ["Content-type"] = "application/json"
          },
          body = req_body,
        })

        assert.res_status(200, res)

        local log_message = wait_for_json_log_entry()
        assert.same("127.0.0.1", log_message.client_ip)
        assert.same(uuid, log_message.request.headers["file-log-uuid"])
        assert.is_number(log_message.request.size)
        assert.is_number(log_message.response.size)
        assert.is_table(log_message.request.body)
        assert.is_table(log_message.request.body_pre)
        assert.is_table(log_message.response.body)
        assert.is_table(log_message.response.body_pre)
        assert.same(req_body, log_message.request.body)
        assert.same(req_body, log_message.request.body_pre)
      end)

      it("logs request and response bodies pre and post transformations", function()
        local uuid = random_string()

        local req_body_pre = {
          hello = "world"
        }

        local req_body_post = {
          hello = "world",
          foo = "bar"
        }

        -- Making the request
        local res = proxy_client:post("/status/200", {
          headers = {
            ["file-log-uuid"] = uuid,
            ["Host"] = "logging.transformed.test",
            ["Content-type"] = "application/json"
          },
          body = req_body_pre,
        })

        assert.res_status(200, res)

        local log_message = wait_for_json_log_entry()
        assert.same("127.0.0.1", log_message.client_ip)
        assert.same(uuid, log_message.request.headers["file-log-uuid"])
        assert.is_number(log_message.request.size)
        assert.is_number(log_message.response.size)
        assert.is_table(log_message.request.body)
        assert.is_table(log_message.request.body_pre)
        assert.is_table(log_message.response.body)
        assert.is_table(log_message.response.body_pre)
        assert.same(req_body_post, log_message.request.body)
        assert.same(req_body_pre, log_message.request.body_pre)
      end)

      it("masks log output per custom_fields_by_lua", function()
        local uuid = random_string()

        local data = {
          users = {
            { id = 1, name = "bob",     email = "bob@example.com" },
            { id = 2, name = "alice",   email = "alice@example.com" },
            { id = 3, name = "charlie", email = "charlie@example.com" }
          },
          teams = {
            {
              team_name = "Alpha",
              members = {
                { id = 4, name = "david", email = "david@example.com" },
                { id = 5, name = "eve",   email = "eve@example.com" }
              }
            },
            {
              team_name = "Beta",
              members = {
                { id = 6, name = "frank", email = "frank@example.com" },
                { id = 7, name = "grace", email = "grace@example.com" }
              }
            }
          },
          organizations = {
            {
              org_id = 1,
              name = "TechCorp",
              departments = {
                {
                  dept_id = 101,
                  name = "Engineering",
                  employees = {
                    { id = 8, name = "henry",  email = "henry@techcorp.com" },
                    { id = 9, name = "isabel", email = "isabel@techcorp.com" }
                  }
                },
                {
                  dept_id = 102,
                  name = "Marketing",
                  employees = {
                    { id = 10, name = "jack", email = "jack@techcorp.com" },
                    { id = 11, name = "kate", email = "kate@techcorp.com" }
                  }
                }
              }
            },
            {
              org_id = 2,
              name = "FinGroup",
              departments = {
                {
                  dept_id = 201,
                  name = "Finance",
                  employees = {
                    { id = 12, name = "leo", email = "leo@fingroup.com" },
                    { id = 13, name = "mia", email = "mia@fingroup.com" }
                  }
                }
              }
            }
          }
        }

        local data_masked_pre = {
          users = {
            { id = 1, name = "bob",     email = "***" },
            { id = 2, name = "alice",   email = "alice@example.com" },
            { id = 3, name = "charlie", email = "charlie@example.com" }
          },
          teams = {
            {
              team_name = "Alpha",
              members = {
                { id = 4, name = "david", email = "david@example.com" },
                { id = 5, name = "eve",   email = "eve@example.com" }
              }
            },
            {
              team_name = "Beta",
              members = {
                { id = 6, name = "frank", email = "frank@example.com" },
                { id = 7, name = "grace", email = "grace@example.com" }
              }
            }
          },
          organizations = {
            {
              org_id = 1,
              name = "TechCorp",
              departments = {
                {
                  dept_id = 101,
                  name = "Engineering",
                  employees = {
                    { id = 8, name = "henry",  email = "henry@techcorp.com" },
                    { id = 9, name = "isabel", email = "isabel@techcorp.com" }
                  }
                },
                {
                  dept_id = 102,
                  name = "Marketing",
                  employees = {
                    { id = 10, name = "jack", email = "jack@techcorp.com" },
                    { id = 11, name = "kate", email = "kate@techcorp.com" }
                  }
                }
              }
            },
            {
              org_id = 2,
              name = "FinGroup",
              departments = {
                {
                  dept_id = 201,
                  name = "Finance",
                  employees = {
                    { id = 12, name = "leo", email = "leo@fingroup.com" },
                    { id = 13, name = "mia", email = "mia@fingroup.com" }
                  }
                }
              }
            }
          }
        }

        local data_masked = {
          foo = "bar", -- added by request-transformer
          users = {
            { id = 1, name = "***",     email = "bob@example.com" },
            { id = 2, name = "***",   email = "alice@example.com" },
            { id = 3, name = "***", email = "charlie@example.com" }
          },
          teams = {
            {
              team_name = "Alpha",
              members = {
                { id = 4, name = "david", email = "***" },
                { id = 5, name = "eve",   email = "***" }
              }
            },
            {
              team_name = "Beta",
              members = {
                { id = 6, name = "frank", email = "***" },
                { id = 7, name = "grace", email = "***" }
              }
            }
          },
          organizations = {
            {
              org_id = 1,
              name = "TechCorp",
              departments = {
                {
                  dept_id = 101,
                  name = "Engineering",
                  employees = {
                    { id = 8, name = "henry",  email = "henry@techcorp.com" },
                    { id = 9, name = "isabel", email = "isabel@techcorp.com" }
                  }
                },
                {
                  dept_id = 102,
                  name = "Marketing",
                  employees = {
                    { id = 10, name = "jack", email = "***" },
                    { id = 11, name = "kate", email = "kate@techcorp.com" }
                  }
                }
              }
            },
            {
              org_id = 2,
              name = "FinGroup",
              departments = {
                {
                  dept_id = 201,
                  name = "Finance",
                  employees = {
                    { id = 12, name = "leo", email = "leo@fingroup.com" },
                    { id = 13, name = "mia", email = "mia@fingroup.com" }
                  }
                }
              }
            }
          }
        }

        -- Making the request
        local res = proxy_client:post("/status/200", {
          headers = {
            ["file-log-uuid"] = uuid,
            ["Host"] = "logging.transformed.test",
            ["Content-type"] = "application/json"
          },
          body = data,
        })

        assert.res_status(200, res)

        local log_message = wait_for_json_log_entry()
        assert.same("127.0.0.1", log_message.client_ip)
        assert.same(uuid, log_message.request.headers["file-log-uuid"])
        assert.is_number(log_message.request.size)
        assert.is_number(log_message.response.size)
        assert.is_table(log_message.request.body)
        assert.is_table(log_message.request.body_pre)
        assert.is_table(log_message.response.body)
        assert.is_table(log_message.response.body_pre)
        assert.same(data_masked, log_message.request.body)
        assert.same(data_masked_pre, log_message.request.body_pre)
      end)
    end)
  end
end
