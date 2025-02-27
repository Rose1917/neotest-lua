local struct = require("neotest-lua.struct")

---@class PointEntry
---@field name string 文件名
---@field path string 文件路径
---@field line table<number, number> 行和行的覆盖次数
---@field orig string 原始文件名

---@param bytes string binary string of data
---@param root string root path
---@param bytes string binary data
---@return PointEntry[] 文件覆盖信息


local cov_hightlight_switch = false
function parse(data, root)
    -- log_info("parsing coverage data:%s", data)
    -- log_info("parsing coverage data:%s", root)
    local filedata = {}  -- Will hold our results
    local n = 0         -- Record counter (for debugging/statistics)
    local i = 1         -- Current byte index
    local data_len = #data

    while i <= data_len do
        if i + 3 > data_len then
            log_error("data_len:%d, i:%d", data_len, i)
            break
        end
        local strlen, new_i = struct.unpack("<I4", data, i)
        i = new_i
        if i + strlen - 1 > data_len then
            log_error("data_len:%d, i:%d, strlen:%d", data_len, i, strlen)
            break
        end

        local str = data:sub(i, i + strlen - 1)
        i = i + strlen
        if i > data_len then
            log_error("data_len:%d, i:%d", data_len, i)
            break
        end
        if i + 7 > data_len then
            log_error("data_len:%d, i:%d", data_len, i)
            break 
        end
        local count, new_i = struct.unpack("<I8", data, i)
        i = new_i
        str = string.gsub(str, "^@+", "")
        local colonCount = select(2, str:gsub(":", ""))
        if colonCount ~= 1 then
            goto continue
        end

        local filename_str, line_str = str:match("([^:]+):(.+)")
        if not filename_str or not line_str then
            print("split fail: " .. str)
            return nil, false
        end

        local line = tonumber(line_str)
        if not line then
            print("atoi fail: " .. str)
            return nil, false
        end

        root = root:gsub("/$", "")
        local abs_path = root .. "/" .. filename_str
        local simple_name = filename_str:match("([^/]+)$") or filename_str

        -- log_info("abs_path:%s, simple_name:%s, line:%d, count:%d", abs_path, simple_name, line, count)

        local found = false
        for _, entry in ipairs(filedata) do
            if entry.path == abs_path then
                entry.line[line] = (entry.line[line] or 0) + count
                found = true
                break
            end
        end

        if not found then
            local newEntry = {
                name = simple_name,
                path = abs_path,
                line = {},
                orig = filename_str,
            }
            newEntry.line[line] = count
            table.insert(filedata, newEntry)
        end

        n = n + 1
        ::continue::
    end
    return filedata, true
end

---@class CovCaseFileData
---@field name string 简单文件名
---@field path string 文件路径
---@field line table<number, number> 行和行的覆盖次数
---@field orig string 原始文件名

---@class CovCaseData
---@field case CovCaseFileData[] 文件数据

---@class CovDataSet
---@field path CovCaseData case的覆盖信息

---@param position_path string case的id
---@param case CovCaseFileData[] case的覆盖信息

---@type table<string, LineInfo>
local cov_data_line_mem = {}
local cov_data_case_mem = {}

-- register a highlight group of light green background as coverage
-- local cov_namespace = vim.api.nvim_create_namespace("NeotestCovNamespace")
local tracked_buffers = {}

-- Register buffer on `BufEnter` event

-- vim.api.nvim_command("highlight NeotestCov guibg=#c8e6c9 guifg=#000000")
local cov_namespace = vim.api.nvim_create_namespace("cov_namespace")

vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
        vim.api.nvim_set_hl(0, 'NeotestCov',  { bg = '#cdf2cd' , blend = 0})  -- Pink background with white text
        vim.api.nvim_set_hl(0, 'NeotestCovVirt', { fg = '#ffcc00', blend=100 })
        local bufnr = vim.api.nvim_get_current_buf()
        local file_path = vim.api.nvim_buf_get_name(bufnr)

        if not tracked_buffers[bufnr] then
            tracked_buffers[bufnr] = file_path
        end
    end
})


local function setup_file_hightlight(bufnr, file_path, line_data)
    vim.api.nvim_buf_clear_namespace(bufnr, cov_namespace, 0, -1)
    for line, count in pairs(line_data) do
        local current_buf = vim.api.nvim_get_current_buf()
        local total_lines = vim.api.nvim_buf_line_count(bufnr)
        if line < 1 or line > total_lines then
            log_error("setup_file_hightlight::invalid line:%s", line)
        end

        -- local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, cov_namespace, 0, -1, {})
        -- log_debug("setup_file_hightlight::extmarks:%s", vim.inspect(extmarks))

        local success, err = pcall(function()
                vim.api.nvim_buf_set_extmark(bufnr, cov_namespace, line - 1, 0, {
                    id = line,
                    hl_group = 'NeotestCov',
                    priority = 10000,
                    end_row = line,
                    virt_text = {{'> ' .. tostring(count), 'NeotestCovVirt'}},
                    virt_text_pos = 'right_align',
                })
            end
        )
        if not success then
            log_error("setup_file_hightlight::error:%s", err)
        end
        -- vim.api.nvim_buf_add_highlight(bufnr, -1, hl_group, line - 1, 0, -1)
    end
end

function on_enter_buffer()
    local file_path = vim.api.nvim_buf_get_name(0)
    if not cov_data_line_mem[file_path] then
        return
    end

    if not cov_hightlight_switch then
        return
    end

    setup_file_hightlight(0, file_path, cov_data_line_mem[file_path])
end


local function setup_hightlight(path, case, cov_data)
    if not (path and case and cov_data) then
        log_error("setup_hightlight:: invalid args:%s, %s, %s", path, case, cov_data)
        return
    end

    for _, cov_case in ipairs(cov_data) do
        local file_path = cov_case.path

        -- init
        cov_data_line_mem[file_path] = cov_data_line_mem[file_path] or {}
        cov_data_case_mem[file_path] = cov_data_case_mem[file_path] or {}

        -- update cov_data_line_mem
        for line, count in pairs(cov_case.line) do
            cov_data_line_mem[file_path][line] = count
            cov_data_case_mem[file_path][line] = cov_data_case_mem[file_path][line] or {}
            table.insert(cov_data_case_mem[file_path][line], case)
        end
        -- TODO:update cov_data_case_mem ???
    end

    -- log_info("setup_hightlight::cov_data_line_mem:%s", vim.inspect(cov_data_line_mem))
    -- log_info("setup_hightlight::cov_data_case_mem:%s", vim.inspect(cov_data_case_mem))
end


local function enable_cov_highlight()
    vim.defer_fn(function()
        -- log_info("enable_cov_highlight::tracked_buffers:%s", vim.inspect(tracked_buffers))
        for bufnr, file_path in pairs(tracked_buffers) do
            if not cov_data_line_mem[file_path] then
                log_info("enable_cov_highlight::no cov data for file:%s", file_path)
                goto continue
            end

            -- log_info("enable_cov_highlight::setup hightlight for file:%s", file_path)
            setup_file_hightlight(bufnr, file_path, cov_data_line_mem[file_path])
            ::continue::
        end
    end, 100)
end

local function disable_cov_highlight()
    for bufnr, file_path in pairs(tracked_buffers) do
        -- test if file_path is in cov_data_line_mem
        if not cov_data_line_mem[file_path] then
            goto continue
        end

        vim.api.nvim_buf_clear_namespace(bufnr, cov_namespace, 0, -1)

        -- 记录一个标记
        ::continue::
    end
end


local function toggle_cov_highlight()
    cov_hightlight_switch = not cov_hightlight_switch
    if cov_hightlight_switch then
        enable_cov_highlight()
    else
        disable_cov_highlight()
    end
end

-- register function: every time opened a buffer, refresh hightlight
vim.api.nvim_command("autocmd BufEnter * lua require('neotest-lua.cov').on_enter_buffer()")

local M = {
    parse                  = parse,
    setup_hightlight       = setup_hightlight,
    on_enter_buffer        = on_enter_buffer,
    enable_cov_highlight   = enable_cov_highlight,
    disable_cov_highlight  = disable_cov_highlight,
    toggle_cov_highlight   = toggle_cov_highlight,
}

return M
