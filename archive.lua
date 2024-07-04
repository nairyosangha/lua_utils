local utils = require 'utils.utils'

local archive = {}
local archive_mt = { __index = archive }
local ZIP = setmetatable({}, archive_mt)
local RAR = setmetatable({}, archive_mt)
local _7Z = setmetatable({}, archive_mt)
local mapper = { CBZ = ZIP, ZIP = ZIP, RAR = RAR, ['7Z'] = _7Z }

-- execute command and return exit code
local function execute(cmd)
    if _VERSION == "Lua 5.1" then
        return os.execute(cmd)
    elseif _VERSION == "Lua 5.2" then
        local success, exit, code = os.execute(cmd)
        return exit == "exit" and code or 1
    end
    assert(true, ("Unsupported lua version: %s!"):format(_VERSION))
end

function archive:new(file_path)
    assert(utils.path_exists(file_path), string.format("INVALID PATH '%q'!", file_path))
    self.ext = utils.get_extension(file_path) or ""
    self.path = file_path
    return setmetatable({}, { __index = mapper[self.ext:upper()] or self })
end

function archive:build_filter(filters)
    if filters == nil then return "*" end
    local str_builder = ""
    for _,f in pairs(filters) do
        str_builder = str_builder .. string.format(" %q ", f)
    end
    return str_builder
end

function _7Z:build_filter(filters)
    if filters == nil then return "'-i!*'" end
    local str_builder = {}
    for _,filter in ipairs(filters) do
        table.insert(str_builder, ("'-i!%s'"):format(filter))
    end
    return table.concat(str_builder, " ")
end

function ZIP:list_files(args)
    local cmd_str = 'unzip -Z -1 %q %s 2>/dev/null'
    local cmd = cmd_str:format(self.path, args.filter and self:build_filter(args.filter) or '')
    return utils.iterate_cmd(cmd)
end

function RAR:list_files(args)
    local cmd_str = 'unrar lb %q %s 2>/dev/null'
    local cmd = cmd_str:format(self.path, args.filter and self:build_filter(args.filter) or '')
    return utils.iterate_cmd(cmd)
end

function _7Z:list_files(args)
    local cmd_str = [[7z l -slt %q %s 2>/dev/null]]
    local cmd = cmd_str:format(self.path, self:build_filter(args.filter))
    local files = {}
    for _,c in ipairs(utils.run_cmd(cmd)) do
        local _,_, path = c:find("^Path = (.+)$")
        if path then
            table.insert(files, path)
        else
            local _,_, size = c:find("^Size = (%d+)")
            if size and size == '0' then -- this is a directory
                table.remove(files, #files)
            end
        end
    end
    return function()
        -- first entry is the 7z file itself
        return table.remove(files, 2)
    end
end

function ZIP:check_valid()
    return execute(("unzip -t %q >/dev/null 2>&1"):format(self.path)) == 0
end

function RAR:check_valid()
    return execute(("unrar t %q >/dev/null 2>&1"):format(self.path)) == 0
end

function _7Z:check_valid()
    return execute(("7z t %q >/dev/null 2>&1"):format(self.path)) == 0
end

-- [] are expanded as pattern in unzip command, to 'escape' them '[' is replaced with '[[]'
function ZIP:replace_left_brackets(filter)
    if filter == nil then return nil end
    local replaced = {}
    for _,v in ipairs(filter) do
        local v_replaced, count = string.gsub(v, "%[", "[[]")
        replaced[#replaced+1] = v_replaced
    end
    return replaced
end

function ZIP:extract(args)
    local cmd = ('unzip -jo %q %s -d %q 2>/dev/null'):format(self.path, self:build_filter(self:replace_left_brackets(args.filter)), args.target_path or ".")
    return utils.iterate_cmd(cmd)
end

function RAR:extract(args)
    local cmd = ('unrar e -y -o+ %q %s %q 2>/dev/null'):format(self.path, args.filter and self:build_filter(args.filter) or '', args.target_path or ".")
    return utils.iterate_cmd(cmd)
end

function _7Z:extract(args)
    local cmd = ('7z e -y %q %s -o%q 2>/dev/null'):format(self.path, self:build_filter(args.filter), args.target_path or ".")
    return utils.iterate_cmd(cmd)
end

return archive
