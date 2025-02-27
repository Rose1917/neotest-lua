local nio = require("nio")
local lib = require("neotest.lib")
local pytest = require("neotest-lua.pytest")
local base = require("neotest-lua.base")
local Path = require("plenary.path")
local log = require("neotest-lua.log")
local cov = require("neotest-lua.cov")
local live_log = require("neotest-lua.livelog")

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
  local function build_script_args(run_args, runner, user_args, stream_path, results_path)
    local script_args = {
        "--stream_file",
        stream_path,
        "--output_file",
        results_path,
    }
    local position = run_args.tree:data()

    if run_args.extra_args then
      vim.list_extend(script_args, run_args.extra_args)
    end

    -- split by filename::test_case: specify the case and file
    local full_file_path
    if position and position.id then
        local parts = vim.split(position.id, "::")
        log_info("file id:%s", position.id)
        if #parts == 2 then
            table.insert(script_args, "--file")
            table.insert(script_args, parts[1])
            full_file_path = parts[1]
            table.insert(script_args, "--case")
            table.insert(script_args, parts[2])
        end
    end

    -- run all test cases in file
    if position and position.type == "file" then
        lib.notify("run all test cases in file")
        full_file_path = position.path
        table.insert(script_args, "--file")
        table.insert(script_args, full_file_path)
    end

    if not full_file_path then
        error("position id is invalid" .. vim.inspect(position))
        return
    end

    -- read server_port.txt
    local user_args = base.parse_args(user_args, {server_port_path = true})
    local port, module = base.get_server_port(user_args.server_port_path, full_file_path)
    if not port then
        error(string.format("parse port failed:please check the server_port.txt file:%s, module is:%s, port:%s",
            user_args.server_port_path, module, port))
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
      log_info("root:%s", root)

      local results_path = nio.fn.tempname()
      local stream_path = nio.fn.tempname()

      -- disable cov highlight
      cov.disable_cov_highlight()
      live_log.clear_all_livelog()
      


      -- print(vim.inspect(position.path))

      lib.files.write(stream_path, "")
      local stream_data, stop_stream = lib.files.stream_lines(stream_path)

      local script_args = build_script_args(args, runner, config.get_args(), stream_path, results_path)
      local script_path, script_dir = base.get_script_path()

      
      -- bender的debug工具可以考慮注入

      -- local strategy_config
      -- if args.strategy == "dap" then
      --   strategy_config =
      --     base.create_dap_config(python_command, script_path, script_args, config.dap_args)
      -- end
      ---@type neotest.RunSpec
      return {
        command = vim.iter({ lua_command, script_path, script_args }):flatten():totable(),
        env = {
            LUA_PATH = string.format("%s%s?.lua", script_dir, Path.path.sep),
            LUA_CPATH = string.format("%s%s?.so", script_dir, Path.path.sep),
        },
        context = {
          results_path = results_path,
          stop_stream = stop_stream,
          root = root,
        },
        stream = function()
          return function()
            local lines = stream_data()
            local results = {}
            for _, line in ipairs(lines) do
              local result = vim.json.decode(line, { luanil = { object = true } })
              _G.log_info("line:%s", line)
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
      log_info("data:%s", data)
      log_info("result:%s", vim.inspect(result))

      local results = vim.json.decode(data, { luanil = { object = true } })

      for _, pos_result in pairs(results) do
          result.output_path = pos_result.output_path
          if pos_result.cov then
              local cov_data = cov.parse(pos_result.cov, spec.context.root)
              log_info("cov:%s", vim.inspect(cov_data))
              log_info("pos_result:%s", vim.inspect(pos_result))
              cov.setup_hightlight(pos_result.full_path, pos_result.case, cov_data)
          end

          if pos_result.live_logs then
              local log_data = pos_result.live_logs
              live_log.setup_livelog(log_data)
              log_info("live_log:%s", vim.inspect(log_data))
          end
      end

      cov.enable_cov_highlight()
      return results
    end,
  }
end
