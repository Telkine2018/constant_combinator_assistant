
local prefix = "cst_comb_assist"

data:extend({
    {
        type = "string-setting",
        name = prefix .. "-allowed",
        setting_type = "startup",
        default_value = "",
        allow_blank = true,
		order="ab"
    },
    {
        type = "int-setting",
        name = prefix .. "-combinator_per_line",
        setting_type = "startup",
        default_value = 4,
		order="ac"
    },
    {
        type = "int-setting",
        name = prefix .. "-slot_per_line",
        setting_type = "startup",
        default_value = 5,
		order="ab"
    },
    {
        type = "bool-setting",
        name = prefix .. "-enabled",
        setting_type = "runtime-per-user",
        default_value = true,
		order="ac"
    }
})



