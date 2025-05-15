log_path = "/tmp/neotest_plug.log"
log_file = io.open(log_path, "w")
print_to_console = false
if not log_file then
    print("failed to open log file: " .. log_path)
    os.exit(1)
end

function log(cate, fmt, ...)
    local time = os.date("%Y-%m-%d %H:%M:%S")
    local msg = string.format(fmt, ...)
    if print_to_console then
        print(time .. " [" .. cate .. "] " .. msg)
    end
    log_file:write(time .. " [" .. cate .. "] " .. msg .. "\n")
    log_file:flush()
end

function _G.log_error(fmt, ...)
    log("ERROR", fmt, ...)
end

function _G.log_info(fmt, ...)
    log("INFO", fmt, ...)
end

function _G.log_debug(fmt, ...)
    log("DEBUG", fmt, ...)
end

