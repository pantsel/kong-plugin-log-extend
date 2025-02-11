# Kong Plugin Log Extend

## Summary

The `log-extend` plugin extends Kong's logging functionality by updating the log serializer to include additional information in the logs. 

It is meant to be used in conjunction with the already provided logging plugins in Kong.

This plugin allows you to include request and response bodies in the logs, add custom fields and mask sensitive information.

The plugin can be configured to include request and response bodies both before and after transformations are applied.

The custom_fields_by_lua extension, allows defining advanced patterns to mask sensitive information within nested objects and lists.

## Code rundown

Files:
- `kong/plugins/log-extend/handler.lua`: Contains the plugin logic.
- `kong/plugins/log-extend/schema.lua`: Contains the plugin configuration schema.

For documentation on the plugin code, please refer to the code.md file located at `kong/plugins/log-extend/code.md`.

## Installation

You can install the plugin either by bundling it with your Kong Gateway image or by using k8s configMap/secrets and Helm.

### Bundle the plugin in your Kong Gateway image

Example `Dockerfile`:

```dockerfile
# Use a minimal base image
FROM debian:bullseye-slim

# Copy the Kong package
COPY kong.deb /tmp/kong.deb

# Install only the necessary dependencies, clean up, and minimize image size
RUN set -eux; \
    apt-get update; \
    apt-get install --yes /tmp/kong.deb; \
    apt-get purge -y dpkg-dev; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/kong.deb; \
    chown kong:0 /usr/local/bin/kong; \
    chown -R kong:0 /usr/local/kong; \
    ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit; \
    ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/lua; \
    ln -s /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx; \
    kong version

# Include custom plugin
COPY kong/plugins/log-extend /usr/local/share/lua/5.1/kong/plugins/log-extend

# Copy entrypoint script and ensure it is executable
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 755 /docker-entrypoint.sh

# Switch to non-root user
USER kong

# Expose only necessary ports (adjust based on your use case)
EXPOSE 8000 8443 8001 8444 8002 8445 8003 8446 8004 8447

# Use a safe stop signal
STOPSIGNAL SIGQUIT

# Healthcheck for Kong
HEALTHCHECK --interval=10s --timeout=10s --retries=3 CMD kong health

# Set the entrypoint
ENTRYPOINT ["/docker-entrypoint.sh"]

# Default command
CMD ["kong", "docker-start"]
```

### Install on K8s dataplanes using configMap and helm

1. Create a secret for the plugin code:

```bash
$ kubectl create configmap kong-plugin-log-extend --from-file=kong/plugins/log-extend -n kong 
```
The results should look like this:

```bash
configmap/kong-plugin-log-extend created
```

2. Update helm values to include the plugin:

```yaml
gateway:
  plugins:
    configMaps:
    - name: kong-plugin-log-extend
      pluginName: log-extend
```

### Enable the plugin

```
KONG_PLUGINS=bundled,my-plugin

or in Helm:

env:
  plugins: bundled,my-plugin
```

References:

- [Plugin Development and distribution](https://docs.konghq.com/gateway/latest/plugin-development/distribution/) 
- [Deploy Plugins](https://docs.konghq.com/gateway/latest/plugin-development/get-started/deploy/)
- [Adding Custom Plugins on Konnect](https://docs.konghq.com/konnect/gateway-manager/plugins/add-custom-plugin/#main)

## Configuration

| Parameter                     | Description                                                          | Type    | Required | Default |
| ----------------------------- | -------------------------------------------------------------------- | ------- | -------- | ------- |
| `config.request_body`         | Include the request body in the logs.                                | boolean | true     | true    |
| `config.request_body_pre`     | Include the request body before transformations in the logs.         | boolean | true     | false   |
| `config.response_body`        | Include the response body in the logs.                               | boolean | true     | true    |
| `config.response_body_pre`    | Include the response body before transformations in the logs.        | boolean | true     | false   |
| `config.extend_on_error`      | Extend the logs only if the response status code is >= 400.          | boolean | true     | false   |
| `config.custom_fields_by_lua` | A map of custom fields to be added to the logs, defined by Lua code. | map     |          |         |

Note that including the request and response bodies in the logs will increase Kong's memory usage and require request buffering to be enabled. You can check the standard log entries that can be modified [here](https://docs.konghq.com/gateway/latest/plugin-development/pdk/kong.log/#konglogserialize).

This plugin modifies the data for any plugin that utilizes the `log.serialize` function. It does not log data to an endpoint but instead changes the content that will be sent through one of the standard logging plugins.

## Example Configuration

Below is an example configuration for the `log-extend` plugin in a `kong.yaml` file:

```yaml
_format_version: "3.0"

plugins:
  - name: file-log
    enabled: true
    config:
      path: /dev/stdout
  # Only apply on global level
  - name: log-extend
    enabled: true
    config:
      include_body: true
      include_body_pre: true
      custom_fields_by_lua:
        request.body.foo: return "[REDACTED]"
        request.body.organizations.1.departments.2.employees.1.email: return "***"
        request.body.teams.*.members.*.email: return "***"
        request.body_pre.users.1.email: return "***"
        request.body.users.*.name: return "***"
        response.body.request.body.teams.1.members.1.email: return "***"
        source: return "kong"
```

## Example Request and Log

### Example Request

```http
POST /example-route HTTP/1.1
Host: localhost:8000
Content-Type: application/json
{
  "foo": "bar",
  "organizations": [
    {
      "departments": [
        {
          "employees": [
            {
              "email": "employee@example.com"
            }
          ]
        }
      ]
    }
  ],
  "teams": [
    {
      "members": [
        {
          "email": "member@example.com"
        }
      ]
    }
  ],
  "users": [
    {
      "name": "user1",
      "email": "user1@example.com"
    }
  ]
}
```

### Example Log

```json
{
  "response": {
    "size": 9982,
    "headers": {
      "access-control-allow-origin": "*",
      "content-length": "9593",
      "date": "Thu, 19 Sep 2024 22:10:39 GMT",
      "content-type": "text/html; charset=utf-8",
      "via": "1.1 kong/3.8.0.0-enterprise-edition",
      "connection": "close",
      "server": "gunicorn/19.9.0",
      "access-control-allow-credentials": "true",
      "x-kong-upstream-latency": "171",
      "x-kong-proxy-latency": "1",
      "x-kong-request-id": "2f6946328ffc4946b8c9120704a4a155"
    },
    "status": 200
  },
  "route": {
    "updated_at": 1726782477,
    "tags": [],
    "response_buffering": true,
    "path_handling": "v0",
    "protocols": [
      "http",
      "https"
    ],
    "service": {
      "id": "fb4eecf8-dec2-40ef-b779-16de7e2384c7"
    },
    "https_redirect_status_code": 426,
    "regex_priority": 0,
    "name": "example_route",
    "id": "0f1a4101-3327-4274-b1e4-484a4ab0c030",
    "strip_path": true,
    "preserve_host": false,
    "created_at": 1726782477,
    "request_buffering": true,
    "ws_id": "f381e34e-5c25-4e65-b91b-3c0a86cfc393",
    "paths": [
      "/example-route"
    ]
  },
  "workspace": "f381e34e-5c25-4e65-b91b-3c0a86cfc393",
  "workspace_name": "default",
  "tries": [
    {
      "balancer_start": 1726783839539,
      "balancer_start_ns": 1.7267838395395e+18,
      "ip": "34.237.204.224",
      "balancer_latency": 0,
      "port": 80,
      "balancer_latency_ns": 27904
    }
  ],
  "client_ip": "192.168.65.1",
  "request": {
    "id": "2f6946328ffc4946b8c9120704a4a155",
    "headers": {
      "accept": "*/*",
      "user-agent": "HTTPie/3.2.3",
      "host": "localhost:8000",
      "connection": "keep-alive",
      "accept-encoding": "gzip, deflate"
    },
    "uri": "/example-route",
    "size": 139,
    "method": "POST",
    "querystring": {},
    "url": "http://localhost:8000/example-route",
    "body": {
      "foo": "[REDACTED]",
      "organizations": [
        {
          "departments": [
            {
              "employees": [
                {
                  "email": "***"
                }
              ]
            }
          ]
        }
      ],
      "teams": [
        {
          "members": [
            {
              "email": "***"
            }
          ]
        }
      ],
      "users": [
        {
          "name": "***",
          "email": "***"
        }
      ]
    }
  },
  "upstream_uri": "/",
  "started_at": 1726783839538,
  "source": "upstream",
  "upstream_status": "200",
  "latencies": {
    "kong": 1,
    "proxy": 171,
    "request": 173,
    "receive": 1
  },
  "service": {
    "write_timeout": 60000,
    "read_timeout": 60000,
    "updated_at": 1726782459,
    "host": "httpbin.konghq.com",
    "name": "example_service",
    "id": "fb4eecf8-dec2-40ef-b779-16de7e2384c7",
    "port": 80,
    "enabled": true,
    "created_at": 1726782459,
    "protocol": "http",
    "ws_id": "f381e34e-5c25-4e65-b91b-3c0a86cfc393",
    "connect_timeout": 60000,
    "retries": 5
  }
}
```

## Development

The repo uses devcontainers for development. To get started, open the project in VSCode and click on the "Reopen in Container" button.
or run the following command:

```bash
devcontainer open .  
```

## Testing

```bash
$ pongo run
```

## License

Use of this software is subject to the terms of your license agreement with Kong Inc.
