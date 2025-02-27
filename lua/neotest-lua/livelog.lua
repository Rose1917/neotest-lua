local struct = require("neotest-lua.struct")
local M = {}

local live_logs_mem = {}
local live_case_mem = {}

-- register a highlight group of light green background as coverage
-- local cov_namespace = vim.api.nvim_create_namespace("NeotestCovNamespace")
local tracked_buffers = {}

-- Register buffer on `BufEnter` event

-- vim.api.nvim_command("highlight NeotestCov guibg=#c8e6c9 guifg=#000000")
local cov_namespace = vim.api.nvim_create_namespace("cov_namespace")

vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        local file_path = vim.api.nvim_buf_get_name(bufnr)

        if not tracked_buffers[bufnr] then
            tracked_buffers[bufnr] = file_path
        end
    end
})


local function setup_file_live_log(bufnr, file_path, line_data)
    -- vim.api.nvim_buf_clear_namespace(bufnr, cov_namespace, 0, -1)
    for line, log_info in pairs(line_data) do
        local buf = vim.api.nvim_create_buf(false, true)
        local width = 50
        local height = 1
        local opts = {
            relative = "cursor",
            row = 1,
            col = 0,
            width = width,
            height = height,
            style = "minimal",
            border = "single",
        }

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {log_info})
        local win = vim.api.nvim_open_win(buf, false, opts)
        -- Close the window after a short delay
        vim.defer_fn(function()
            vim.api.nvim_win_close(win, true)
        end, 2000) -- Close after 2 seconds
    end
end

function on_enter_buffer()
    local file_path = vim.api.nvim_buf_get_name(0)
    if not cov_data_line_mem[file_path] then
        return
    end

    setup_file_live_log(0, file_path, cov_data_line_mem[file_path])
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

local function setup_livelog(data)
    for file_path, line_data in pairs(data) do
        live_logs_mem[file_path] = line_data
        log_info("setup_livelog::live_logs_mem:%s::%s",file_path,vim.inspect(line_data))
    end
end

local pop_up_windows = {}
local last_line = -1

local function show_log_info()
    vim.defer_fn(function()
        -- get current buffer file_path and line
        local bufnr = vim.api.nvim_get_current_buf()
        local file_path = vim.api.nvim_buf_get_name(bufnr)
        local line = vim.api.nvim_win_get_cursor(0)[1]

        if last_line == line then
            return
        end

        line = tostring(line)
        if pop_up_windows[bufnr] and pop_up_windows[bufnr][last_line] then
            vim.api.nvim_win_close(pop_up_windows[bufnr][last_line], true)
            pop_up_windows[bufnr][last_line] = nil
        end

        -- test if file_path is in live_logs_mem
        if not live_logs_mem[file_path] then
            return
        end

        if not live_logs_mem[file_path][line] then
            return
        end

        local content = live_logs_mem[file_path][line]

        -- show log info
        local buf = vim.api.nvim_create_buf(false, true)
        local width = 200
        local height = #content
        local opts = {
            relative = "cursor",
            row = 1,
            col = 0,
            width = width,
            height = height,
            style = "minimal",
            border = "single",
        }

        -- local log_info = table.concat(live_logs_mem[file_path][line], "\n")

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
        local win = vim.api.nvim_open_win(buf, false, opts)

        pop_up_windows[bufnr] = pop_up_windows[bufnr] or {}
        pop_up_windows[bufnr][line] = win
        last_line = line
    end
    , 100)

end

local function disable_cov_highlight()
    for bufnr, file_path in pairs(tracked_buffers) do
        -- test if file_path is in cov_data_line_mem
        if not cov_data_line_mem[file_path] then
            goto continue
        end

        vim.api.nvim_buf_clear_namespace(bufnr, cov_namespace, 0, -1)
        ::continue::
    end
end

local function clear_all_livelog()
    if pop_up_windows then
        for bufnr, line_win in pairs(pop_up_windows) do
            for line, win in pairs(line_win) do
                vim.api.nvim_win_close(win, true)
                pop_up_windows[bufnr][line] = nil
            end
        end
    end

    live_logs_mem = {}
    live_case_mem = {}
end


local M = {
    parse                  = parse,
    setup_hightlight       = setup_hightlight,
    on_enter_buffer        = on_enter_buffer,
    show_log_info   = show_log_info,
    setup_livelog         = setup_livelog,
    clear_all_livelog      = clear_all_livelog,
}


-- register function: every time moved cursor in normal mode, show log info
vim.api.nvim_command("autocmd CursorMoved * lua require('neotest-lua.livelog').show_log_info()")
return M
