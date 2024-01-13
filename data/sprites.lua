local commons = require("scripts.commons")

local prefix = commons.prefix

---@param name string
---@return string
local function png(name) return (commons.graphic_path):format(name) end


local function np(name)
    return prefix .. "-" .. name
end


data:extend({
    {
        type = "sprite",
        name = "plus",
        filename = png("plus"),
        position = { 0, 0 },
        size = 32,
        flags = {
            "icon" }
    },
    {
        type = "sprite",
        name = "minus",
        filename = png("minus"),
        position = { 0, 0 },
        size = 32,
        flags = { "icon" }
    },
    {
        type = "sprite",
        name = np("line-selector"),
        filename = png("line-selector"),
        position = { 0, 0 },
        size = 32,
        flags = {
            "icon" }
    },
    {
        type = "sprite",
        name = np("sort"),
        filename = png("sort"),
        position = { 0, 0 },
        size = 32,
        flags = {
            "icon" }
    },

    {
        type = "virtual-signal",
        name = np("global_signal"),
        icon = png("global_signal"),
        icon_size = 64,
        order = "z-a"
      },
    
})
