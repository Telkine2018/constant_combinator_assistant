---@diagnostic disable: missing-fields
local util = require("__core__/lualib/util")

local tools = require("scripts.tools")
local commons = require("scripts.commons")

---@class GuiCombinatorInfo
---@field id integer
---@field combinator LuaEntity
---@field frame LuaGuiElement
---@field slot_index integer ?
---@field line_index integer ?
---@field parameters ConstantCombinatorParameters[]
---@field slot_table LuaGuiElement
---@field count_field LuaGuiElement
---@field slot_per_line integer
---@field slot_count integer
---@field multiplier_cb LuaGuiElement
---@field player_index integer
---@field changed boolean
---@field enabled_field LuaGuiElement
---@field neg_field LuaGuiElement
---@field previous_multiplier number?
---@field slot_count_map table<integer, integer>
local Gui = {}

local mt = { __index = Gui }


local multipliers = {
    x1 = 1,
    x10 = 2,
    x100 = 3,
    x1000 = 4,
    x10000 = 5,
    xStack = 6
}

local prefix = commons.prefix

local function np(name)
    return prefix .. "-" .. name
end

local slot_table_name = np("slot-table")
local global_frame_name = np("global-frame")

local global_signal = commons.global_signal
local excluded_names = {}

for token in string.gmatch(settings.startup[np("allowed")].value --[[@as string]], "[^%s]+") do
    table.insert(excluded_names, token)
end

local combinator_per_line = settings.startup[prefix .. "-combinator_per_line"].value --[[@as integer]]
local slot_per_line = settings.startup[prefix .. "-slot_per_line"].value --[[@as integer]]

local multipliers_values = { 1, 10, 100, 1000, 10000, 1 }

---@param player LuaPlayer
---@return LuaGuiElement?
local function get_global_frame(player)
    local vars = tools.get_vars(player)
    return vars[global_frame_name] --[[@as LuaGuiElement]]
end

---@param player LuaPlayer
---@param new_frame LuaGuiElement?
local function set_global_frame(player, new_frame)
    local vars = tools.get_vars(player)
    vars[global_frame_name] = new_frame
end

---@type fun(base:string, prefix:string):boolean
local string_starts_with = util.string_starts_with

---@return EntityMap<GuiCombinatorInfo>
local function combinator_map()
    local map = global.combinator_map
    return map --[[@as EntityMap<GuiCombinatorInfo>]]
end

---@param player_index integer
---@return GuiCombinatorInfo
local function get_current(player_index)
    local vars = tools.get_vars(game.players[player_index])
    return vars.cc_current --[[@as GuiCombinatorInfo]]
end

---@param player_index integer
---@param current GuiCombinatorInfo?
local function set_current(player_index, current)
    local vars = tools.get_vars(game.players[player_index])
    vars.cc_current = current
end

---@param element LuaGuiElement
function Gui.get_frame(element)
    while element ~= nil do
        if element.tags.id then return element end
        element = element.parent
    end
    return nil
end

-- #region Object methods

---@param line_index integer
---@return integer
function Gui:get_first_button_of_line(line_index)
    return (line_index - 1) * (self.slot_per_line) + 1
end

---@param line_index integer
---@return LuaGuiElement
function Gui:get_line_button(line_index)
    return self.slot_table.children[self:get_first_button_of_line(line_index)]
end

---@param slot_index integer
---@return LuaGuiElement
function Gui:get_slot_button(slot_index)
    local i = slot_index - 1
    local slot_per_line = self.slot_per_line
    return self.slot_table.children[math.floor(i / slot_per_line) *
    (slot_per_line + 1) + (i % slot_per_line) + 2]
end

---@param slot_index integer
function Gui:display_slot_button(slot_index)
    if not slot_index or slot_index == 0 then return end
    local button = self:get_slot_button(slot_index)
    local parameter = self.parameters[slot_index]

    if parameter and parameter.signal then
        button.elem_value = parameter.signal
        button.label.caption = util.format_number(parameter.count, true)
        button.tooltip = ""
    else
        button.elem_value = nil
        button.label.caption = ""
        button.tooltip = { prefix .. "-tooltip.button_without_item" }
    end
end

---@param line_index integer?
function Gui:select_line(line_index)
    if not line_index then return end

    local start = self:get_first_button_of_line(line_index)
    for i = start, start + self.slot_per_line - 1 do
        self:select_button(i, true)
    end
end

---@param line_index integer?
function Gui:unselect_line(line_index)
    if not line_index then return end

    local start = self:get_first_button_of_line(line_index)
    for i = start, start + self.slot_per_line - 1 do self:unselect_button(i) end
end

---@param slot_index integer?
function Gui:unselect_button(slot_index)
    if not (slot_index) then return end
    local previous = self:get_slot_button(slot_index)
    previous.locked = true
    previous.style = "slot_button"
end

---@param slot_index integer?
---@param locked boolean
function Gui:select_button(slot_index, locked)
    if not (slot_index) then return end
    local button = self:get_slot_button(slot_index)
    button.locked = locked
    button.style = "yellow_slot_button"
end

---@param self GuiCombinatorInfo
function Gui:set_count_field()
    if not self.slot_index then
        self.count_field.enabled = false
        self.count_field.text = ""
        return
    end
    local p = self.parameters[self.slot_index]
    if not p.signal then
        self.count_field.enabled = false
        self.count_field.text = ""
    else
        self.count_field.enabled = true
        local multiplier = self:get_multiplier(false)
        self.count_field.text = tostring(math.floor(p.count / multiplier))
        self.previous_multiplier = multiplier
    end
end

---@param player_index integer
function Gui.unselect_current(player_index)
    local current = get_current(player_index)
    if current then
        current:unselect_button(current.slot_index)
        current:unselect_line(current.line_index)
        current.slot_index = nil
        current.line_index = nil
        current:set_count_field()
        current.previous_multiplier = nil
        set_current(player_index)
    end
end

---@param player_index integer
---@param info GuiCombinatorInfo?
---@param slot_index integer
function Gui.select_current_button(player_index, info, slot_index)
    Gui.unselect_current(player_index)
    if not (info) then return end
    info:select_button(slot_index, false)
    info.slot_index = slot_index
    if info.parameters[slot_index].signal then
        info.count_field.enabled = true
        local multiplier = info:get_multiplier(false)
        local count = info.parameters[slot_index].count
        info.neg_field.state = count < 0
        if count < 0 then count = -count end
        info.count_field.text = tostring(math.floor(count / multiplier))
        info.previous_multiplier = multiplier
    end
    set_current(player_index, info)
end

---@param info GuiCombinatorInfo?
---@param line_index integer
function Gui.select_current_line(info, line_index)
    if info then
        Gui.unselect_current(info.frame.player_index)
    end
    if not (info) then return end
    info:select_line(line_index)
    info.line_index = line_index
    set_current(info.frame.player_index, info)
end

-- #endregion

---@param element LuaGuiElement
---@return GuiCombinatorInfo?
function Gui.get_info(element)
    local frame = Gui.get_frame(element)
    if not frame then return nil end

    local id = frame.tags.id
    return combinator_map()[id]
end

---Close current ui
---@param element LuaGuiElement
function Gui.close(element)
    if not (element and element.valid) then return end
    local frame = Gui.get_frame(element)
    if not frame then return end

    local id = frame.tags.id
    local map = combinator_map()
    ---@cast id -nil
    local info = map[id]
    local current = get_current(frame.player_index)
    if info == current then set_current(frame.player_index, nil) end
    map[id] = nil
    frame.destroy()
end

---@param player_index integer
function Gui.autosave(player_index)
    if tools.get_vars(game.players[player_index]).autosave then
        Gui.save_all(player_index)
    end
end

---@param player LuaPlayer
---@param entity LuaEntity
function Gui.create(player, entity)
    local map = combinator_map()
    local info = map[entity.unit_number]
    if info then return end

    ---@type GuiCombinatorInfo
    info = {
        combinator = entity,
        id = entity.unit_number,
        player_index = player.index
    }
    map[info.id] = info
    setmetatable(info, mt)

    local cc = entity

    local gframe = get_global_frame(player)
    local gtable
    if not gframe or not gframe.valid then
        gframe = player.gui.screen.add {
            type = "frame",
            direction = 'vertical',
            name = prefix .. "-frame"
        }

        local titleflow = gframe.add { type = "flow" }
        local title_label = titleflow.add {
            type = "label",
            caption = { prefix .. "-frame.cc_title" },
            style = "frame_title",
            ignored_by_interaction = true
        }
        local drag = titleflow.add {
            type = "empty-widget",
            style = "flib_titlebar_drag_handle"
        }
        drag.drag_target = gframe
        titleflow.drag_target = gframe
        titleflow.add {
            type = "sprite-button",
            name = np("cc-close-all"),
            style = "frame_action_button",
            mouse_button_filter = { "left" },
            sprite = "utility/close_white",
            hovered_sprite = "utility/close_black"
        }

        set_global_frame(player, gframe)

        gtable = gframe.add {
            type = "table",
            column_count = combinator_per_line,
            name = "table",
            draw_vertical_lines = true,
            draw_horizontal_line = true
        }

        local bflow = gframe.add { type = "flow", direction = "horizontal" }
        bflow.style.top_margin = 10

        local b = bflow.add {
            type = "button",
            caption = { prefix .. "-button.apply" },
            name = prefix .. "-cc-apply",
            tooltip = { prefix .. "-tooltip.save" }
        }
        b.style.width = 80
        b = bflow.add {
            type = "button",
            caption = { prefix .. "-button.close" },
            name = prefix .. "-cc-close",
            tooltip = { prefix .. "-tooltip.close" }
        }
        b.style.width = 80

        local autocb = bflow.add {
            type = "checkbox",
            caption = { prefix .. "-field.autosave" },
            name = prefix .. "-autosave",
            state = false
        }
        autocb.state = tools.get_vars(game.players[player.index]).autosave or
            false

        bflow.add {
            type = "sprite-button",
            name = np("sort"),
            mouse_button_filter = { "left" },
            tooltip = { np("button.sort-tooltip") },
            style = "tool_button",
            sprite = np("sort")
        }

        gframe.force_auto_center()
    else
        gtable = gframe.table
    end
    player.opened = gframe

    local frame = gtable.add {
        type = "frame",
        direction = 'vertical',
        tags = { id = entity.unit_number }
    }
    frame.tags.id = entity.unit_number
    info.frame = frame

    local inner_frame = frame.add {
        type = "frame",
        style = "inside_shallow_frame_with_padding",
        direction = "vertical"
    }

    local cb = cc.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]

    local scroll_frame = inner_frame.add {
        type = "frame",
        style = "inset_frame_container_frame"
    }
    scroll_frame.style.bottom_margin = 10
    scroll_frame.style.padding = { 5, 5, 5, 5 }
    local scroll = scroll_frame.add {
        type = "scroll-pane",
        horizontal_scroll_policy = "never"
    }

    local parameters = cb.parameters
    info.parameters = parameters

    for _, p in pairs(parameters) do
        if p.signal and not p.signal.name then p.signal = nil end
    end

    info.slot_per_line = slot_per_line
    info.slot_count = cb.signals_count

    local slot_table = scroll.add {
        type = "table",
        column_count = slot_per_line + 1,
        name = slot_table_name
    }
    info.slot_table = slot_table

    ---@type LuaGuiElement?
    local flow
    local line_index = 1
    for i = 1, info.slot_count do
        local parameter = parameters[i]
        local signal = parameter.signal

        if i % slot_per_line == 1 then
            local b = slot_table.add {
                type = "sprite-button",
                sprite = prefix .. "-line-selector",
                tags = { line_index = line_index },
                style = "tool_button",
                tooltip = { prefix .. "-tooltip.line_button" }
            }
            line_index = line_index + 1
        end

        local button = slot_table.add {
            type = "choose-elem-button",
            elem_type = "signal",
            signal = signal,
            style = "flib_slot_default",
            tags = { slot_index = i }
        }
        -- selected: style="yellow_slot_button"

        local label = button.add {
            type = "label",
            name = "label",
            style = "count_label_bottom",
            ignored_by_interaction = true
        }
        if signal then
            label.caption = util.format_number(parameter.count, true)
        else
            button.tooltip = { prefix .. "-tooltip.button_without_item" }
        end

        button.locked = true
    end

    local count_panel = inner_frame.add {
        type = "flow",
        direction = "horizontal"
    }
    info.count_field = count_panel.add {
        type = "textfield",
        name = "count",
        numeric = true,
        allow_negative = true
    }
    info.count_field.style.width = 60
    info.count_field.enabled = false
    info.count_field.style.top_margin = 4

    local mp_flow = count_panel.add { type = "flow", direction = "vertical" }
    mp_flow.style.vertical_spacing = 0
    local b = mp_flow.add {
        type = "sprite-button",
        sprite = "plus",
        name = prefix .. "-plus"
    }
    b.style.width = 16
    b.style.height = 16
    b = mp_flow.add {
        type = "sprite-button",
        sprite = "minus",
        name = prefix .. "-minus"
    }
    b.style.width = 16
    b.style.height = 16

    local items = {
        { prefix .. "-items.x1" }, { prefix .. "-items.x10" },
        { prefix .. "-items.x100" }, { prefix .. "-items.x1000" },
        { prefix .. "-items.x10000" }, { prefix .. "-items.xStack" }
    }

    local index = #items + 1
    local slot_count_map = {}
    local wagons = game.get_filtered_entity_prototypes({
        { filter = "type", type = "cargo-wagon" }
    })
    for _, wagon in pairs(wagons) do
        table.insert(items, {
            "", "x [item=" .. wagon.name .. "] ", wagon.localised_name
        })
        slot_count_map[index] = wagon.get_inventory_size(defines.inventory
            .cargo_wagon)
        info.slot_count_map = slot_count_map
        index = index + 1
    end

    local multiplier_cb = count_panel.add {
        type = "drop-down",
        items = items,
        selected_index = 1,
        name = prefix .. "-multiplier"
    }
    multiplier_cb.style.width = 180
    multiplier_cb.style.top_margin = 6
    info.multiplier_cb = multiplier_cb

    local state_flow = inner_frame.add { type = "flow", direction = "horizontal" }
    state_flow.style.top_margin = 5
    info.enabled_field = state_flow.add {
        type = "checkbox",
        caption = { prefix .. "-field.enabled" },
        state = cb.enabled
    }

    info.neg_field = state_flow.add {
        type = "checkbox",
        caption = { prefix .. "-field.negative" },
        state = false,
        name = prefix .. "-negative"
    }
    info.neg_field.style.left_margin = 10
end

---@param shift boolean
---@return integer
function Gui:get_multiplier(shift)
    local p = self.parameters[self.slot_index]
    local multiplier = 1
    local multiplier_index = self.multiplier_cb.selected_index
    if shift and p.signal then
        if p.signal and p.signal.type == 'fluid' then
            multiplier_index = multipliers.x10000
        elseif p.signal and p.signal.type == 'item' then
            multiplier_index = multipliers.xStack
        end
    end
    if multiplier_index == multipliers.xStack then
        if p.signal and p.signal.type == "item" then
            multiplier = game.item_prototypes[p.signal.name].stack_size
        end
    else
        multiplier = multipliers_values[multiplier_index]
        if not multiplier then
            local slot_count = self.slot_count_map[multiplier_index]
            if slot_count and p.signal and p.signal.type == "item" then
                multiplier = game.item_prototypes[p.signal.name].stack_size *
                    slot_count
            end
        end
    end
    if not multiplier then multiplier = 1 end
    return multiplier
end

---@param e EventData.on_gui_click
function Gui.add_const(e, constant)
    local info = Gui.get_info(e.element)
    if not info then return end
    if not info.slot_index then return end

    if info.neg_field.state then constant = -constant end
    local p = info.parameters[info.slot_index]
    local count = p.count
    local multiplier = info:get_multiplier(e.shift)
    count = math.floor((count + constant * multiplier) / multiplier) *
        multiplier
    p.count = count
    info.neg_field.state = count < 0
    if count < 0 then count = -count end
    info.count_field.text = tostring(math.floor(count / multiplier))
    info:display_slot_button(info.slot_index)
    info.changed = true
    Gui.autosave(e.player_index)
end

---@param e EventData.on_gui_click
tools.on_gui_click(np("plus"), function(e) Gui.add_const(e, 1) end)

---@param e EventData.on_gui_click
tools.on_gui_click(np("minus"), function(e) Gui.add_const(e, -1) end)

---@param e EventData.on_gui_text_changed
local function on_gui_text_changed(e)
    local info = Gui.get_info(e.element)
    if not info then return end

    if e.element == info.count_field then
        if not info.slot_index then return end

        local value = tonumber(e.text)
        if not value then return end
        local multiplier = info:get_multiplier(false)
        value = value * multiplier
        if info.neg_field.state then value = -value end
        info.parameters[info.slot_index].count = value
        info:display_slot_button(info.slot_index)
        info.changed = true
        Gui.autosave(e.player_index)
    end
end
tools.on_event(defines.events.on_gui_text_changed, on_gui_text_changed)

---@param e EventData.on_gui_checked_state_changed
tools.on_event(defines.events.on_gui_checked_state_changed, function(e)
    if e.element and e.element.name == prefix .. "-autosave" then
        tools.get_vars(game.players[e.player_index]).autosave = e.element.state
    elseif e.element and e.element.name == prefix .. "-negative" then
        local info = Gui.get_info(e.element)
        if not info then return end
        if not info.slot_index then return end

        local p = info.parameters[info.slot_index]
        local count = p.count
        p.count = -count

        info:display_slot_button(info.slot_index)
        info.changed = true
        Gui.autosave(e.player_index)
    end
end)

---@param e EventData.on_gui_selection_state_changed
tools.on_event(defines.events.on_gui_selection_state_changed, function(e)
    if e.element and e.element.name == prefix .. "-multiplier" then
        local info = Gui.get_info(e.element)
        if not info then return end

        if not info.slot_index or info.slot_index == 0 then
            info.previous_multiplier = nil
            return
        end

        if not info.previous_multiplier then
            info.previous_multiplier = info:get_multiplier(false)
            return
        end

        local value = tonumber(info.count_field.text)
        if not value then return end

        value = value * info.previous_multiplier
        info.previous_multiplier = info:get_multiplier(false)
        value = math.floor(value / info.previous_multiplier)
        if value < 1 then value = 1 end

        info.count_field.text = tostring(value)
        local parameter = info.parameters[info.slot_index]
        if not parameter then return end

        if info.neg_field.state then value = -value end

        parameter.count = value * info.previous_multiplier
        info:display_slot_button(info.slot_index)
        info.changed = true
        Gui.autosave(e.player_index)
    end
end)

---@param e EventData.on_gui_click
function Gui.processs_slot_button(e)
    local button = e.element
    local info = Gui.get_info(button)
    if not info then return end

    local new_index = button.tags.slot_index --[[@as integer]]

    local alt, shift, control = e.alt, e.shift, e.control

    if e.button == 2 then
        local current = get_current(button.player_index)

        if shift then
            if current and current.slot_index then
                if info == current and new_index == current.slot_index then
                    return
                else
                    local previous_button =
                        current:get_slot_button(current.slot_index)
                    local previous_signal = previous_button.elem_value
                    previous_button.elem_value = button.elem_value
                    button.elem_value = previous_signal

                    local p1 = current.parameters[current.slot_index]
                    local p2 = info.parameters[new_index]

                    if not control then
                        current.parameters[current.slot_index] = {
                            count = p2.count,
                            signal = p2.signal and
                                { name = p2.signal.name, type = p2.signal.type },
                            index = current.slot_index
                        }
                    end

                    info.parameters[new_index] = {
                        count = p1.count,
                        signal = p1.signal and
                            { name = p1.signal.name, type = p1.signal.type },
                        index = new_index
                    }

                    current:display_slot_button(current.slot_index)
                    info:display_slot_button(new_index)
                    info.changed = true
                    current.changed = true
                    Gui.autosave(e.player_index)
                end
            end
        end
        Gui.select_current_button(e.player_index, info, new_index)
    elseif e.button == 4 then
        if not (shift or control) then
            info.parameters[new_index].signal = nil
            info:display_slot_button(new_index)
            Gui.select_current_button(e.player_index, info, new_index)
            Gui.autosave(e.player_index)
            info.changed = true
        elseif shift then
            Gui.unselect_current(e.player_index)
            for i = info.slot_count - 1, new_index, -1 do
                local p1 = info.parameters[i]
                local p2 = info.parameters[i + 1]
                p2.signal = p1.signal
                p2.count = p1.count
                info:display_slot_button(i + 1)
            end

            info.parameters[new_index].signal = nil
            info.parameters[new_index].count = 0
            info:display_slot_button(new_index)
            info.changed = true
            Gui.autosave(e.player_index)
            return
        elseif control then
            Gui.unselect_current(e.player_index)
            for i = new_index, info.slot_count - 1 do
                local p1 = info.parameters[i]
                local p2 = info.parameters[i + 1]
                p1.signal = p2.signal
                p1.count = p2.count
                Gui.display_slot_button(info, i)
            end
            local i = info.slot_count
            info.parameters[i].signal = nil
            info.parameters[i].count = 0
            info:display_slot_button(i)
            info.changed = true
            Gui.autosave(e.player_index)
            return
        end
    end
end

---@param e EventData.on_gui_click
function Gui.process_line_button(e)
    local line = e.element
    local info = Gui.get_info(line)
    if not info then return end

    local new_index = line.tags.line_index --[[@as integer]]
    local alt, shift, control = e.alt, e.shift, e.control

    if e.button == 2 then
        local current = get_current(e.player_index)
        if shift then
            if current and current.line_index then
                if info == current and new_index == current.line_index then
                    return
                else
                    if info.slot_per_line == current.slot_per_line then
                        local start1 = info:get_first_button_of_line(new_index)
                        local start2 = current:get_first_button_of_line(
                            current.line_index)

                        for i = 0, info.slot_per_line - 1 do
                            info.parameters[start1 + i], current.parameters[start2 +
                            i] = current.parameters[start2 + i],
                                info.parameters[start1 + i]
                            info.parameters[start1 + i].index = start1 + i
                            current.parameters[start2 + i].index = start2 + i
                            info:display_slot_button(start1 + i)
                            current:display_slot_button(start2 + i)
                        end
                        info.changed = true
                        current.changed = true
                    end
                    Gui.autosave(e.player_index)
                end
            end
        end
        Gui.select_current_line(info, new_index)
    elseif e.button == 4 then
        if shift then
            local start = info:get_first_button_of_line(new_index)
            for dst = info.slot_count, start + info.slot_per_line, -1 do
                info.parameters[dst].signal =
                    info.parameters[dst - info.slot_per_line].signal
                info.parameters[dst].count =
                    info.parameters[dst - info.slot_per_line].count
                info:display_slot_button(dst)
            end
            for dst = start, start + info.slot_per_line - 1 do
                info.parameters[dst].signal = nil
                info:display_slot_button(dst)
            end
            info.changed = true
            Gui.autosave(e.player_index)
            Gui.unselect_current(e.player_index)
        elseif control then
            local start = info:get_first_button_of_line(new_index)
            local delta = info.slot_per_line
            for i = start, info.slot_count do
                local src = i + delta
                if src > info.slot_count then
                    for j = i, info.slot_count do
                        info.parameters[j].signal = nil
                        info:display_slot_button(j)
                    end
                    goto end_loop
                end
                info.parameters[i].signal = info.parameters[src].signal
                info.parameters[i].count = info.parameters[src].count
                info.changed = true
                info:display_slot_button(i)
            end
            ::end_loop::
            Gui.autosave(e.player_index)
            Gui.unselect_current(e.player_index)
        end
    end
end

---@return integer?
function Gui:save()
    if not (self.combinator and self.combinator.valid) then return nil end

    local cb = self.combinator.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
    cb.parameters = self.parameters
    cb.enabled = self.enabled_field.state
    self.changed = false

    local p = self.parameters[1]
    if p.signal and p.signal.name == global_signal then return p.count end
    return nil
end

---@param e EventData.on_gui_click
local function on_click(e)
    if not (e.element and e.element.valid) then return end

    if e.element and e.element.valid and e.element.parent and
        e.element.parent.valid and e.element.parent.name == slot_table_name then
        if e.element.tags.slot_index then
            Gui.processs_slot_button(e)
        elseif e.element.tags.line_index then
            Gui.process_line_button(e)
        end
    end
end
tools.on_event(defines.events.on_gui_click, on_click)

---@param e EventData.on_gui_elem_changed
local function on_gui_elem_changed(e)
    if not (e.element and e.element.valid) then return end

    local button = e.element
    if button.parent.name ~= slot_table_name then return end

    local info = Gui.get_info(button)
    if not info then return end
    if not button.tags.slot_index then return end

    local new_index = e.element.tags.slot_index --[[@as integer]]
    local signal = button.elem_value --[[@as SignalID]]
    if signal and signal.type == 'virtual' and
        (signal.name == 'signal-everything' or signal.name == 'signal-anything' or
            signal.name == 'signal-each') then
        return
    end

    info.parameters[new_index].signal = signal
    info.parameters[new_index].count = 1
    local multiplier = info:get_multiplier(false)
    info.parameters[new_index].count = multiplier

    info:display_slot_button(new_index)
    Gui.autosave(e.player_index)
    Gui.set_count_field(info)
end
tools.on_event(defines.events.on_gui_elem_changed, on_gui_elem_changed)

---@param player LuaPlayer
function Gui.close_global_frame(player)
    local gframe = get_global_frame(player)
    if not gframe then return end
    gframe.destroy()
    set_global_frame(player, nil)
end

---@param player_index integer
---@param save boolean?
---@param global_save boolean?
function Gui.close_all(player_index, save, global_save)
    local map = combinator_map()
    local copy = tools.table_copy(map)

    local global_values = {}
    for _, info in pairs(copy) do
        if info.player_index == player_index then
            if save then
                local global_index = info:save()
                if global_index and not global_values[global_index] then
                    global_values[global_index] = info.parameters
                end
            end
            Gui.close(info.frame)
        end
    end
    if global_save then Gui.update_global_combinator(global_values) end
    Gui.close_global_frame(game.players[player_index])
end

---@param player_index integer
---@param global_save boolean?
function Gui.save_all(player_index, global_save)
    local map = combinator_map()
    local global_values = {}
    for _, info in pairs(map) do
        if info.player_index == player_index then
            local global_index = info:save()
            if global_index and not global_values[global_index] then
                global_values[global_index] = info.parameters
            end
        end
    end
    if global_save then Gui.update_global_combinator(global_values) end
end

---@param global_values table<integer, ConstantCombinatorParameters[]>
function Gui.update_global_combinator(global_values)
    if not next(global_values) then return end

    for _, surface in pairs(game.surfaces) do
        local cc_list = surface.find_entities_filtered {
            type = "constant-combinator"
        }
        if cc_list and #cc_list > 0 then
            for _, cc in pairs(cc_list) do
                local cb = cc.get_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
                if cb then
                    local signal = cb.get_signal(1)
                    if signal and signal.signal and signal.signal.name ==
                        global_signal then
                        local source = global_values[signal.count]
                        if source then
                            cb.parameters = source
                        end
                    end
                end
            end
        end
    end
end

---@param signal SignalID
---@return string
---@return string
local function get_order(signal)
    local order, subgroup_order
    if signal.type == "item" then
        local proto = game.item_prototypes[signal.name]
        subgroup_order = proto.subgroup.order
        order = "A" .. proto.group.order .. "  " .. subgroup_order .. "  " .. proto.order
    elseif signal.type == "fluid" then
        local proto = game.fluid_prototypes[signal.name]
        subgroup_order = proto.subgroup.order
        order = "B" .. proto.group.order .. "  " .. subgroup_order .. "  " .. proto.order
    elseif signal.type == "virtual" then
        if signal.name == global_signal then
            order = "_"
        else
            local proto = game.virtual_signal_prototypes[signal.name]
            subgroup_order = proto.subgroup.order
            order = "C" .. proto.subgroup.order .. "  " .. proto.order
        end
    else
        return "", ""
    end
    return order, subgroup_order
end

---@class SortElement : ConstantCombinatorParameters
---@field order string
---@field subgroup_order string

---@param player_index integer
---@param per_subgroup boolean
function Gui.sort(player_index, per_subgroup)
    Gui.unselect_current(player_index)

    local map = combinator_map()

    ---@type GuiCombinatorInfo[]
    local info_table = {}
    for _, info in pairs(map) do
        if info.player_index == player_index then
            table.insert(info_table, info)
        end
    end
    if #info_table == 0 then return end
    table.sort(info_table, function(info1, info2) return info1.frame.index < info2.frame.index end)

    ---@type table<string, SortElement>
    local signal_map = {}
    for _, info in pairs(info_table) do
        local parameters = info.parameters
        if parameters then
            for _, p in pairs(parameters) do
                if p.signal and p.signal.type and p.signal.name then
                    local name = p.signal.type .. "/" .. p.signal.name
                    local prev = signal_map[name]
                    if not prev then
                        local order, subgroup_order = get_order(p.signal)
                        signal_map[name] = {
                            count = p.count,
                            signal = p.signal,
                            order = order,
                            subgroup_order = subgroup_order
                        }
                    else
                        prev.count = prev.count + p.count
                    end
                end
            end
        end
    end

    ---@type SortElement[]
    local signal_list = tools.table_copy(signal_map)
    table.sort(signal_list, function(i1, i2) return i1.order < i2.order end)

    local info_index = 1
    ---@type GuiCombinatorInfo?
    local info
    local signals_count
    local dst_index
    local subgroup_order
    local src_index = 1
    ::restart::
    while ( src_index <= #signal_list ) do
        if not info then
            if info_index > #info_table then
                goto skip_info
            end
            info = info_table[info_index]
            signals_count = #info.parameters
            info_index = info_index + 1
            dst_index = 1
        end
        local src_p = signal_list[src_index]
        local dst_p
        if per_subgroup and subgroup_order ~= src_p.subgroup_order then
            while (dst_index - 1) % info.slot_per_line ~= 0 and dst_index <= signals_count do
                dst_p = info.parameters[dst_index]
                dst_p.signal = nil
                info:display_slot_button(dst_index)
                dst_index = dst_index + 1
            end
            if dst_index > signals_count then
                goto next_info
            end
        end
        dst_p = info.parameters[dst_index]
        dst_p.signal = src_p.signal
        dst_p.count = src_p.count
        info:display_slot_button(dst_index)
        subgroup_order = src_p.subgroup_order
        dst_index = dst_index + 1
        src_index = src_index + 1
        ::next_info::
        if dst_index > signals_count then
            info = nil
        end
    end
    ::skip_info::
    if per_subgroup and src_index <= #signal_list then
        per_subgroup = false
        src_index = 1
        info_index = 1
        info = nil
        subgroup_order = nil
        goto restart
    end

    if info then
        for i = dst_index, #info.parameters do
            info.parameters[i].signal = nil
            info:display_slot_button(i)
        end
    end
    if info_index <= #info_table then
        while info_index <= #info_table do
            info = info_table[info_index]
            for i = 1, #info.parameters do
                info.parameters[i].signal = nil
                info:display_slot_button(i)
            end
            info_index = info_index + 1
        end
    end
    Gui.autosave(player_index)
end

tools.on_gui_click(np("cc-close-all"),
    ---@EventData.on_gui_click
    function(e)
        Gui.close_all(e.player_index, false)
    end)

tools.on_gui_click(np("sort"),
    ---@EventData.on_gui_click
    function(e)
        Gui.sort(e.player_index, e.shift)
    end)

---@param e EventData.on_gui_confirmed
tools.on_event(defines.events.on_gui_confirmed, function(e)
    local info = Gui.get_info(e.element)
    if not info then return end

    if e.control then
        Gui.close_all(e.player_index, true)
    else
        Gui.save_all(e.player_index)
    end
end)

---@param player_index integer
function Gui.check_remaining_frame(player_index)
    if not get_global_frame(game.players[player_index]) then return end
    for _, frame in pairs(combinator_map()) do
        if frame.player_index == player_index then return end
    end
    Gui.close_all(player_index)
end

tools.on_gui_click(prefix .. "-cc-apply", ---@EventData.on_gui_click
    function(e)
        if e.control then
            Gui.close_all(e.player_index, true)
        else
            Gui.save_all(e.player_index, e.shift)
        end
    end)

tools.on_gui_click(prefix .. "-cc-close", ---@EventData.on_gui_click
    function(e) Gui.close_all(e.player_index, true, e.shift) end)

---@EventData.on_gui_confirmed
tools.on_event(defines.events.on_gui_confirmed,
    function(e) Gui.close_all(e.player_index, true) end)

---@param e EventData.on_gui_opened
local function on_gui_opened(e)
    local player = game.players[e.player_index]
    local entity = e.entity

    if not (entity and entity.valid and entity.type == "constant-combinator") then
        return
    end
    if not player.mod_settings[prefix .. "-enabled"].value then return end

    local gframe = get_global_frame(player)
    if not gframe then
        if entity.name ~= "constant-combinator" then return end
    end

    local name = entity.name
    if name ~= "constant-combinator" then
        for _, token in pairs(excluded_names) do
            if string.find(name, token) then return end
        end
    end
    player.opened = nil
    Gui.create(player, entity)
end

tools.on_event(defines.events.on_gui_opened, on_gui_opened)

--[[
---@param e EventData.on_gui_closed
local function on_gui_closed(e)
    local player = game.players[e.player_index]

    if e.entity  and e.entity.type == "constant-combinator" then
        Gui.close_all(e.player_index)
    end
end
tools.on_event(defines.events.on_gui_closed, on_gui_closed)
--]]
----------------------------------------------------------

---@param evt EventData.on_pre_player_mined_item|EventData.on_entity_died|EventData.script_raised_destroy
local function on_destroyed(evt)
    local entity = evt.entity

    if entity.type ~= "constant-combinator" then return end

    local map = combinator_map();
    for _, info in pairs(map) do
        if info.id == entity.unit_number then
            Gui.close(info.frame)
            Gui.check_remaining_frame(info.player_index)
            return
        end
    end
end

local entity_filter = { { filter = 'type', type = 'constant-combinator' } }

tools.on_event(defines.events.on_pre_player_mined_item, on_destroyed, entity_filter)
tools.on_event(defines.events.on_robot_pre_mined, on_destroyed, entity_filter)
tools.on_event(defines.events.on_entity_died, on_destroyed, entity_filter)
tools.on_event(defines.events.script_raised_destroy, on_destroyed, entity_filter)

tools.on_load(function()
    local map = combinator_map()
    for _, info in pairs(map) do setmetatable(info, mt) end
end)

tools.on_init(function() global.combinator_map = {} end)

return Gui
