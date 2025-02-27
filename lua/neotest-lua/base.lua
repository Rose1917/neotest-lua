local nio = require("nio")
local lib = require("neotest.lib")
local Path = require("plenary.path")

local M = {}

function M.is_test_file(file_path)
  -- only check lua files
  if not vim.endswith(file_path, ".lua") then
    return false
  end
  local elems = vim.split(file_path, Path.path.sep)
  local file_name = elems[#elems]

  -- file content must contains unit_test_functions
  -- if lib.process.run(vim.iter({ "grep", "-q", "unit_test_functions", file_path }):flatten():totable()) ~= 0 then
  --   return false
  -- end

  return vim.startswith(file_name, "test_") and vim.endswith(file_name, ".lua")
end

M.module_exists = function(module, python_command)
  return lib.process.run(vim
    .iter({
      python_command,
      "-c",
      "import " .. module,
    })
    :flatten()
    :totable()) == 0
end

local python_command_mem = {}

---@return string[]
function M.get_python_command(root)
  root = root or vim.loop.cwd()
  if python_command_mem[root] then
    return python_command_mem[root]
  end
  -- Use activated virtualenv.
  if vim.env.VIRTUAL_ENV then
    python_command_mem[root] = { Path:new(vim.env.VIRTUAL_ENV, "bin", "python").filename }
    return python_command_mem[root]
  end

  for _, pattern in ipairs({ "*", ".*" }) do
    local match = nio.fn.glob(Path:new(root or nio.fn.getcwd(), pattern, "pyvenv.cfg").filename)
    if match ~= "" then
      python_command_mem[root] = { (Path:new(match):parent() / "bin" / "python").filename }
      return python_command_mem[root]
    end
  end

  if lib.files.exists("Pipfile") then
    local success, exit_code, data = pcall(lib.process.run, { "pipenv", "--py" }, { stdout = true })
    if success and exit_code == 0 then
      local venv = data.stdout:gsub("\n", "")
      if venv then
        python_command_mem[root] = { Path:new(venv).filename }
        return python_command_mem[root]
      end
    end
  end

  if lib.files.exists("pyproject.toml") then
    local success, exit_code, data = pcall(
      lib.process.run,
      { "poetry", "run", "poetry", "env", "info", "-p" },
      { stdout = true }
    )
    if success and exit_code == 0 then
      local venv = data.stdout:gsub("\n", "")
      if venv then
        python_command_mem[root] = { Path:new(venv, "bin", "python").filename }
        return python_command_mem[root]
      end
    end
  end

  -- Fallback to system Python.
  python_command_mem[root] = {
    nio.fn.exepath("python3") or nio.fn.exepath("python") or "python",
  }
  return python_command_mem[root]
end

function M.get_lua_command()
  return { nio.fn.exepath("lua") or "lua" }
end

function M.parse_args(args, allowed_keys)
    local ret = {}
    local skip = false
    for i = 1, #args do
        if skip then
            skip = false
            goto continue
        end

        if args[i]:sub(1, 2) == "--" then
            local key = args[i]:sub(3)
            if not allowed_keys[key] then
                skip = true
            end
            ret[key] = args[i + 1]
            skip = true
        end

        ::continue::
    end

    return ret
end

---@param server_port_path string
---@param relative_path string
---@return number|nil

port_mem = {}
function M.get_server_port(server_port_path, full_file_path)
    if not server_port_path then
        return
    end

    -- the file has many lines, each line has format module:port
    if not port_mem[server_port_path] then
        local lines = lib.files.read_lines(Path:new(server_port_path):expand())
        for _, line in ipairs(lines) do
            local parts = vim.split(line, ":")
            if #parts == 2 then
                port_mem[parts[1]] = parts[2]
            end
        end
    end

    -- TODO:extract module from relative_path
    -- 这里应该做成可定制的
    local patterns = {
        ".*ptest/cases/([^/]+)",
        ".*bin/([^/]+).*",
    }

    for _, pattern in ipairs(patterns) do
        local module = full_file_path:match(pattern)
        if module then
            return port_mem[module], module
        end
    end

    error("module not found".. full_file_path)
end

M.treesitter_queries = [[
    (function_declaration
    name: (method_index_expression
        table: (identifier) @table.name
        method: (identifier) @test.name)
      (#eq? @table.name "unit_test_functions")
    )
    @test.definition
  ]]

    --   ;; Match undecorated functions
    -- ((function_definition
    --   name: (identifier) @test.name)
    --   (#match? @test.name "^test"))
    --   @test.definition
    --
    -- ;; Match decorated function, including decorators in definition
    -- (decorated_definition
    --   ((function_definition
    --     name: (identifier) @test.name)
    --     (#match? @test.name "^test")))
    --     @test.definition
    --
    -- ;; Match decorated classes, including decorators in definition
    -- (decorated_definition
    --   (class_definition
    --    name: (identifier) @namespace.name))
    --   @namespace.definition
    --
    -- ;; Match undecorated classes: namespaces nest so #not-has-parent is used
    -- ;; to ensure each namespace is annotated only once
    -- (
    --  (class_definition
    --   name: (identifier) @namespace.name)
    --   @namespace.definition
    --  (#not-has-parent? @namespace.definition decorated_definition)
    -- )


M.get_root =
    lib.files.match_root_pattern("ptest", "luahelper.json")
    -- lib.files.match_root_pattern("ptest", "pyproject.toml", "setup.cfg", "mypy.ini", "pytest.ini", "setup.py", "luahelper.json")

---@return string
function M.get_script_path()
  local paths = vim.api.nvim_get_runtime_file("neotest-lua.lua", true)
  for _, path in ipairs(paths) do
      -- return dir of path
    return path, Path:new(path):parent().filename
  end

  error(debug.traceback("neotest-lua.lua not found"))
end

function M.create_dap_config(python_path, script_path, script_args, dap_args)
  return vim.tbl_extend("keep", {
    type = "python",
    name = "Neotest Debugger",
    request = "launch",
    python = python_path,
    program = script_path,
    cwd = nio.fn.getcwd(),
    args = script_args,
  }, dap_args or {})
end

local stored_runners = {}

function M.get_runner(python_path)
  local command_str = table.concat(python_path, " ")
  if stored_runners[command_str] then
    return stored_runners[command_str]
  end
  local vim_test_runner = vim.g["test#python#runner"]
  if vim_test_runner == "pyunit" then
    return "unittest"
  end
  if
      vim_test_runner and lib.func_util.index({ "unittest", "pytest", "django" }, vim_test_runner)
  then
    return vim_test_runner
  end
  local runner = M.module_exists("pytest", python_path) and "pytest"
      or M.module_exists("django", python_path) and "django"
      or "unittest"
  stored_runners[command_str] = runner
  return runner
end

return M
