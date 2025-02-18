#!/usr/local/bin/lua
-- @desc: 一个用来发送测试命令的客户端脚本
-- @usage: lua sender.lua --file <message> --case <case1> --case <case2> ...
-- @author: pedroren
-- @date: 2025-02-13

-- 解析命令行参数
---@return file string @文件名
---@return cases list @测试用例
function parse_args(args)
    local file = nil
    local cases = {}
    local port
    local skip = false
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

    if #cases == 0 then
        print("missing argument: --case")
        os.exit(1)
    end

    if not port then
        print("missing argument: --port")
        os.exit(1)
    end

    return port, file, cases
end

function send_message(port, file, cases)
    local socket = require("socket")
    local host = "127.0.0.1" -- 可配置为服务器的IP地址

    -- Create a TCP client socket
    local client = assert(socket.tcp())
    client:settimeout(5)  -- Set timeout to 5 seconds

    -- Connect to the server
    assert(client:connect(host, port))

    -- Prepare the command message (adjust as needed)
    local message = file .. " " .. table.concat(cases, " ") .. '\n'

    -- Send the message
    assert(client:send(message))
    print("message sent successfully:", message)

    client:close()
end


--------------- main ------------------------
if #arg < 2 then
    print("usage: hive sender.lua --file <message> --case <case1> --case <case2> ...")
    os.exit(1)
end

local port, file, cases = parse_args(arg)
send_message(port, file, cases)
---------------------------------------------
