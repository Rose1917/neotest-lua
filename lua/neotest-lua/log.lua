local logger = {

}
logger.log_path = "/tmp/neotest_plug.log"
logger.log_file = nil
logger.log_file = logger.log_file or nil

logger.__index = logger

function log(cate, fmt, ...)
    if not logger.log_file then
        logger.log_file = io.open(logger.log_path, "w")
        if not logger.log_file then
            print("failed to open log file: " .. logger.log_path)
            os.exit(1)
        end
    end

    local info = debug.getinfo(3, "Sl")  -- 2 表示调用 log 函数的上一级
    local filename = info.source:sub(2)  -- 去掉文件名前的 '@'
    local line = info.currentline

    local time = os.date("%Y-%m-%d %H:%M:%S")
    local msg = string.format(fmt, ...)
    print(time .. " [" .. cate .. "] " .. "[" .. filename .. ":" .. tostring(line) .. "]:" .. msg .. '\n')
    logger.log_file:write(time .. " [" .. cate .. "] " .. "[" .. filename .. "]:" .. tostring(line) .. ":" .. msg .. '\n')
    logger.log_file:flush()
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

setmetatable(logger, {
    __gc = function(self)
        if self.log_file then
            self.log_file:close()
        end
    end
})
