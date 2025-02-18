local nio = require("nio")
local lib = require("neotest.lib")
local pytest = require("neotest-lua.pytest")
local base = require("neotest-lua.base")

---@class neotest-python._AdapterConfig
---@field dap_args? table
---@field pytest_discovery? boolean
---@field is_test_file fun(file_path: string):boolean
---@field get_python_command fun(root: string):string[]
---@field get_args fun(runner: string, position: neotest.Position, strategy: string): string[]
---@field get_runner fun(python_command: string[]): string

---@param config neotest-python._AdapterConfig
---@return neotest.Adapter
return function(config)
  ---@param run_args neotest.RunArgs
  ---@param results_path string
  ---@param stream_path string
  ---@param runner string
  ---@return string[]
  local function build_script_args(run_args, runner, user_args)
    local script_args = {}
    local position = run_args.tree:data()

    if run_args.extra_args then
      vim.list_extend(script_args, run_args.extra_args)
    end

    -- split by filename::test_case
    local relative_path
    if position and position.id then
        local parts = vim.split(position.id, "::")
        if #parts == 2 then
            table.insert(script_args, "--file")
            relative_path = (parts[1]):match("bin/(.*)")
            if not relative_path then
                error(string.format("invalid path:%s", parts[1]))
                return 
            end

            table.insert(script_args, relative_path)
            table.insert(script_args, "--case")
            table.insert(script_args, parts[2])
        end
    end

    -- read server_port.txt
    local user_args = base.parse_args(user_args, {server_port_path = true})
    local port = base.get_server_port(user_args.server_port_path, relative_path)
    if not port then
        error(string.format("parse port failed:please check the server_port.txt file:%s, module is:%s", user_args.server_port_path, relative_path))
        return 
    end

    table.insert(script_args, "--port")
    table.insert(script_args, port)

    return script_args
  end

  ---@type neotest.Adapter
  return {
    name = "neotest-lua",
    root = base.get_root,
    filter_dir = function(name)
      return name ~= "venv"
    end,
    is_test_file = config.is_test_file,
    discover_positions = function(path)
      local root = base.get_root(path) or vim.loop.cwd() or ""

      local lua_command = base.get_lua_command(root)
      -- local runner = config.get_runner(python_command)

      -- 不需要namespace. 后续如果发现测试太复杂，再酌情加上
      local positions = lib.treesitter.parse_positions(path, base.treesitter_queries, {
        require_namespaces = false,
      })

      return positions
    end,
    ---@param args neotest.RunArgs
    ---@return neotest.RunSpec
    build_spec = function(args)
      local position = args.tree:data()
      local root = base.get_root(position.path) or vim.loop.cwd() or ""
      local lua_command = base.get_lua_command(root)

      local results_path = nio.fn.tempname()
      local stream_path = nio.fn.tempname()

      lib.files.write(stream_path, "")
      local stream_data, stop_stream = lib.files.stream_lines(stream_path)

      local script_args = build_script_args(args, runner, config.get_args())
      local script_path = base.get_script_path()

      io.open('log.txt', 'a'):write(vim.inspect(config.get_args()) .. '\n')

      -- bender的debug工具可以考慮注入

      -- local strategy_config
      -- if args.strategy == "dap" then
      --   strategy_config =
      --     base.create_dap_config(python_command, script_path, script_args, config.dap_args)
      -- end

      ---@type neotest.RunSpec
      return {
        command = vim.iter({ lua_command, script_path, script_args }):flatten():totable(),
        context = {
          results_path = results_path,
          stop_stream = stop_stream,
        },
        stream = function()
          return function()
            local lines = stream_data()
            local results = {}
            for _, line in ipairs(lines) do
              local result = vim.json.decode(line, { luanil = { object = true } })
              results[result.id] = result.result
            end
            return results
          end
        end,
        strategy = strategy_config,
      }
    end,
    ---@param spec neotest.RunSpec
    ---@param result neotest.StrategyResult
    ---@return neotest.Result[]
    results = function(spec, result)
      spec.context.stop_stream()
      local success, data = pcall(lib.files.read, spec.context.results_path)
      if not success then
        data = "{}"
      end
      local results = vim.json.decode(data, { luanil = { object = true } })
      for _, pos_result in pairs(results) do
        result.output_path = pos_result.output_path
      end
      return results
    end,
  }
end
