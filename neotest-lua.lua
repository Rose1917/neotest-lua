#!/usr/local/bin/lua

local json = require("json")
--- add the path of current file dir to lua library

-- @desc: 一个用来发送测试命令的客户端脚本
-- @usage: lua sender.lua --file <message> --case <case1> --case <case2> ...
-- @author: pedroren
-- @date: 2025-02-13

log_path = "/tmp/neotest.log"
log_file = io.open(log_path, "w")
print_to_console = true
enable_color = true


local colors = {
    red = "\x1b[31m",
    green = "\x1b[32m",
    yellow = "\x1b[33m",
    blue = "\x1b[34m",
    magenta = "\x1b[35m",
    cyan = "\x1b[36m",
    white = "\x1b[37m",
    reset = "\x1b[0m",
    default = "\x1b[0m"
}

local function render(text, color)
    color = color or "default"
    if not enable_color then
        return text
    end

    return (colors[color] or colors.yellow) .. text .. colors.reset
end

if not log_file then
    print("failed to open log file: " .. log_path)
    os.exit(1)
end

function log(cate, fmt, ...)
    local time = os.date("%Y-%m-%d %H:%M:%S")
    local msg = string.format(fmt, ...)
    if print_to_console then
        print(time .. " [" .. cate .. "] " .. msg .. "\n")
    end
    log_file:write(time .. " [" .. cate .. "] " .. msg .. "\n")
    log_file:flush()
end

function log_error(fmt, ...)
    log("ERROR", fmt, ...)
end

function log_info(fmt, ...)
    log("INFO", fmt, ...)
end

function log_debug(fmt, ...)
    log("DEBUG", fmt, ...)
end

-- 解析命令行参数
---@return file string @文件名
---@return cases list @测试用例
function parse_args(args)
    local file = nil
    local cases = {}
    local port
    local skip = false
    local stream_file = nil
    local output_file = nil
    for i = 1, #args do
        if skip then
            skip = false
            goto continue
        end

        if args[i] == "--file" then
            file = args[i + 1]
            skip = true
        elseif args[i] == "--case" then
            table.insert(cases, args[i + 1])
            skip = true
        elseif args[i] == "--port" then
            port = tonumber(args[i + 1])
            skip = true
        elseif args[i] == "--stream_file" then
            stream_file = args[i + 1]
            skip = true
        elseif args[i] == "--output_file" then
            output_file = args[i + 1]
            skip = true
        else 
            print("invalid argument: " .. args[i])
            os.exit(1)
        end

        ::continue::
    end

    if not file then
        print("missing argument: --file")
        os.exit(1)
    end

    if not port then
        print("missing argument: --port")
        os.exit(1)
    end

    if not stream_file then
        print("missing argument: --stream_file")
        os.exit(1)
    end

    if not output_file then
        print("missing argument: --output_file")
        os.exit(1)
    end

    return port, file, cases, stream_file, output_file
end

local line_result_template = [[
{
    "id": "<id>",
    "result": {
        "short": "<short>",
        "status": "<status>",
        "errors": []
    }
}
]]

local final_line_result_template = [[
"<id>":{
        "status": "<status>",
        "errors": [<errors>],
        "short": "<short>"
    }
]]

local error_template = [[
{
    "message": "<message>",
    "line": <line>
}
]]

---@class LineResult
---@field log_content string

---@class FileLiveLogItem
---@type table<number, LineResult>

local function process_live_log(base_dir, logs)
    -- for each line, extract the file and line
    ---@type table<string, FileLiveLogItem>
    local live_logs = {}

    local last_file = nil
    local last_level = nil
    local last_line_no = nil

    for line in logs:gmatch("[^\n]+") do
        -- [20250225 22:34:43][TEST][INFO    ][(ptest/session.lua:49) (Lua)] hijackt session success:54300413057
        -- local date, _, level, file, line_no, msg = line:match("^%[([^%]]*)%]" -- date
        -- "%[TEST%]" -- TEST
        -- %[([^%]]*)%] --LEVEL
        -- %[%( 
        --     ([^%):]+)
        --     :(%d+)
        -- %)
        local date, level, file, line_no, mod, msg = line:match("^%[([^%]]*)%]%[TEST%]%[([^%]]*)%]%[%(([^%):]+):(%d+)%)([^%]]*)%](.*)$")
        log_debug("process_live_log::date: %s, level: %s, file: %s, line_no: %s, mod: %s, msg: %s", date, level, file, line_no, mod, msg)

        line_no = tonumber(line_no)

        if file then
            file = base_dir .. file
        end

        if date and level and file and line_no and mod and msg then
            line_no = tostring(line_no)
            last_file = file
            last_level = level
            last_line_no = line_no

            live_logs[last_file] = live_logs[last_file] or {}
            live_logs[last_file][line_no] = live_logs[last_file][line_no] or {}
            log_debug("process_live_log::last_file: %s, last_line_no: %s, msg: %s", last_file, last_line_no, msg)
            table.insert(live_logs[last_file][line_no], msg)
        else
            if last_file and last_line_no then
                live_logs[last_file] = live_logs[last_file] or {}
                live_logs[last_file][last_line_no] = live_logs[last_file][last_line_no] or {}
                table.insert(live_logs[last_file][last_line_no], line)
                log_debug("process_live_log::last_file: %s, last_line_no: %s, line: %s", last_file, last_line_no, line)
            end
        end
    end

    -- print the live logs
    for file, lines in pairs(live_logs) do
        for line_no, logs in pairs(lines) do
            for idx, log in ipairs(logs) do
                log_info("debug:::%s:%s:%s", type(file), type(line_no), type(log))
            end
        end
    end

    return live_logs
end

---@param data result 返回的结构化表
---@param results table 结果集合
---@param relative_path string 相对路径
---@param base string 基础路径
---@param full_path string 完整路径
local function try_process_case(data, results, relative_path, base, full_path)
    local ok = data.status
    local error_str
    local errors = {}
    local id = data.id

    -- 从[xxx]::[xxx]中解析出path和case. 这里的path是相对路径
    local path, case = id:match("%[(.+)%]::%[(.+)%]")
    if not path or not case then
        log_error("invalid id: " .. id)
        os.exit(1)
    end

    local local_id = base .. path .. "::" .. case
    local status = ok and "passed" or "failed"

    -- 总结错误信息
    local short 


    -- 失败，提取错误信息
    if not ok then
        error_str = data.result
        -- log_info("\nerror_str: " .. error_str)
        --  ptest/cases/lobby/test_small_rp.lua:172: LuaUnit test FAILURE: expected: 0, actual: 1
        -- local pattern = ".*" .. relative_path:gsub("([%.%^%$%(%)%+%-%?%[%]{}|\\])", "%%%1") .. ":(%d+):(.+)"

        short = render("case::" .. case .. "failed:" .. error_str,  "red")

        local pattern = "^([^:]+):(%d+):(.+)"
        local err_file, line_no, msg = error_str:match(pattern)

        -- TODO:这里目前看只能支持当前文件的错误
        if line_no and msg and err_file and err_file == relative_path then
            line_no = tonumber(line_no)
            line_no = line_no - 1
            table.insert(errors, {
                message = msg,
                line = line_no
            })
        end
    else
        short = render("case::" .. case .. " passed", "green")
    end

    local live_log = process_live_log(base, data.log)

    local line_result = {
        id = local_id,
        result = {
            short = short,
            status = status,
            errors = errors,
            log = data.log,
            cov = data.cov,
            case = case,
            live_logs = live_log,
            full_path = full_path,
        }
    }

    results[local_id] = {
        status = status,
        errors = errors,
        short  = short,
        case   = case,
        log    = data.log,
        live_logs = live_log,
        cov    = data.cov,
        full_path = full_path,
    }
    
    -- log_info("line_result: \n" .. json.encode(line_result))

    return line_result
end

local function render_log(log)
    -- split the log by '\n'
    local lines = {}
    local level_colors = {
        DEBUG = "cyan",
        INFO = "green",
        WARN = "yellow",
        ERROR = "red",
        FATAL = "magenta",
        TRACE = "cyan",
    }

    local last_level = "INFO"
    for line in log:gmatch("[^\n]+") do
        local date, _, level, msg = line:match("^%[([^%]]*)%]%[([^%]]*)%]%[([^%]]*)%](.*)")
        log_debug("date: %s, level: %s, msg: %s", date, level, msg)
        if date and _ and level and msg then
            level = level:match("^%s*(.-)%s*$"):upper()
            last_level = level
        else
            level = last_level
        end

        local color = level_colors[level]
        table.insert(lines, render(line, color))
    end

    return table.concat(lines, "\n")
end


local function log_output(results, filename, cases)
    -- summary of the results
    local total = 0
    local passed = 0
    local failed = 0

    -- calculate the total, passed, failed
    for _, result in pairs(results) do
        total = total + 1
        if result.status == "passed" then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    -- output the summary
    print(
        render("summary of running [", "cyan") .. render(filename, "blue") .. render("] ", "cyan") .. '\n' ..
        render("total:  ", "cyan") .. render(tostring(total), "white") .. " ✨" .. '\n' ..
        render("passed:  ", "cyan") .. render(tostring(passed), "green") .. " 🎉" .. '\n' ..
        render("failed:  ", "cyan") .. render(tostring(failed), "red") .. " 💔" .. '\n'
    )

    -- divide line
    print(render("----------------------------------------------------------------------------------", "green"))

    -- output the details
    for _, result in pairs(results) do
        local status = result.status
        local id = result.id
        local errors = result.errors
        local short = result.short
        local case = result.case

        print(
            render("case [", "cyan") .. render(case, "blue") .. render("] ", "cyan") .. 
            render("status: ", "cyan") .. render(status, status == "passed" and "green" or "red") .. 
            (status == "passed" and render("  ", "green") or render("  ", "red")) .. '\n'
            -- render("case short summary: \n", "cyan") .. render(short, "white") .. '\n'
        )

        print(render_log(result.log))
    end

    -- divide line
    print(render("----------------------------------------------------------------------------------", "green"))


end

local function check_file_path(full_file_path)
    local relative_path = full_file_path:match(".*/bin/(.+)$")
    if not relative_path then
        print("invalid file path: " .. full_file_path)
        print("path should be absolute path of the file in the bin directory")
        os.exit(1)
    end

    return relative_path, full_file_path:sub(1, #full_file_path - #relative_path)
end

function send_message(port, full_file_path, cases, stream_file, output_file)
    local socket = require("socket")
    local host = "127.0.0.1" -- 可配置为服务器的IP地址

    -- Create a TCP client socket
    local client = assert(socket.tcp())
    client:settimeout(5)  -- Set timeout to 5 seconds

    -- log_info("connecting to server:%s::%s", host, port)
    assert(client:connect(host, port))
    -- log_info("connected to server:%s::%s", host, port)

    local relative_path, base = check_file_path(full_file_path)
    local msg = {
        filename = relative_path,
        cases = cases,
        mode = (cases and #cases > 0) and "single" or "all",
        enable_cov = true,
    }

    local encoded_msg = json.encode(msg)
    if not encoded_msg or #encoded_msg == 0 then
        log_error("encode json error")
        os.exit(1)
    end


    local msg_size = string.pack(">I8", #encoded_msg)

    assert(client:send(msg_size))
    assert(client:send(encoded_msg))

    -- log_info("send message: \n" .. encoded_msg)

    -- 准备接收数据
    local stream = io.open(stream_file, "w")
    if not stream then
        log_error("failed to open stream file: " .. stream_file)
        os.exit(1)
    end

    -- log_info("stream_file:%s" ,stream_file)
    -- log_info("output_file:%s" ,output_file)

    local results = {}
    local cnt = 0
    while (#cases == 0 or cnt < #cases) do
        local response, err = client:receive(8)
        if err then
            if #cases == 0 then
                log_info("no more data to receive")
                break
            end

            log_error("receive header error: " .. err)
            os.exit(1)
        end

        -- TODO: 这里需要处理下大小端问题
        local data_len = string.unpack(">I8", response)
        -- log_info("data_len: " .. data_len)

        -- receive the data
        local response, err = client:receive(data_len)
        if err then
            log_error("receive body error: " .. err)
            os.exit(1)
        end

        -- log_info("response: " .. response)

        local data = json.decode(response)
        if not data then
            print("decode json error, invalid response: " .. response)
            os.exit(1)
        end

        local single_result = try_process_case(data, results, relative_path, base, full_file_path)
        -- log_info("single_result: \n" .. json.encode(single_result))
        stream:write(json.encode(single_result))
        stream:flush()

        cnt = cnt + 1
    end

    client:close()

    log_info("output_file: %s", output_file)
    local output = io.open(output_file, "w")
    local final_result = json.encode(results)
    local ok = output:write(final_result)
    if not ok then
        log_error("failed to write final result to file: " .. output_file)
        os.exit(1)
    end
    -- log_info("final_result: \n" .. final_result)

    log_output(results, relative_path, cases)

    output:close()
    stream:close()
end


--------------- main ------------------------
if #arg < 2 then
    print("usage: hive sender.lua --file <message> --stream_file <stream_file> --output_file <output_file> --case <case1> --case <case2> ...")
    os.exit(1)
end

local port, file, cases, stream_file, output_file = parse_args(arg)
send_message(port, file, cases, stream_file, output_file)
---------------------------------------------
