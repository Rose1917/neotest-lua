--[[
 * Copyright (c) 2015-2020 Iryont <https://github.com/iryont/lua-struct>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
]]

local unpack = table.unpack or _G.unpack

local struct = {}

function struct.unpack(format, data, offset)
    if format == "<I8" then
        -- Unpack a little-endian 8-byte unsigned integer
        local b1, b2, b3, b4, b5, b6, b7, b8 = string.byte(data, offset, offset + 7)
        local value = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216 +
                      b5 * 4294967296 + b6 * 1099511627776 +
                      b7 * 281474976710656 + b8 * 72057594037927936
        return value, offset + 8
    elseif format == "<I4" then
        -- Unpack a little-endian 4-byte unsigned integer
        local b1, b2, b3, b4 = string.byte(data, offset, offset + 3)
        local value = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        return value, offset + 4
    else
        error("unsupported format: " .. format)
    end
end

return struct
