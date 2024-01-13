

local styles = data.raw["gui-style"].default

styles["count_label_bottom"] = {
    type = "label_style",
    parent = "count_label",
    height = 36,
    width = 36,
    vertical_align = "bottom",
    horizontal_align = "right",
    right_padding = 2
}
styles["count_label_top"] = {
    type = "label_style",
    parent = "count_label_bottom",
    vertical_align = "top",
}

styles["count_label_center"] = {
    type = "label_style",
    parent = "count_label_bottom",
    vertical_align = "center",
}
