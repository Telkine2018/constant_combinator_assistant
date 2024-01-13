

local tools = require("scripts.tools")

local prefix = "cst_comb_assist"
local modpath = "__constant_combinator_assistant__"

local commons = {

	prefix = prefix ,
    modpath = modpath,
	graphic_path = modpath .. '/graphics/%s.png',
	global_signal = prefix .. "-global_signal",
}

---@param name string
---@return string
function commons.png(name) return (commons.graphic_path):format(name) end


return commons
