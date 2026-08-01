require("prototypes.styles")

-- GUI sprites, referenced by name from control-stage code.
for _, spec in ipairs({
  { name = "bch-lanes-1", file = "lanes-1.png" },
  { name = "bch-lanes-2", file = "lanes-2.png" },
  { name = "bch-lock-closed", file = "lock-closed.png" },
  { name = "bch-lock-open", file = "lock-open.png" },
}) do
  data:extend({
    {
      type = "sprite",
      name = spec.name,
      filename = "__BeltCapacityHelper__/graphics/" .. spec.file,
      size = 32,
      flags = { "gui-icon" },
    },
  })
end

data:extend({
  {
    type = "custom-input",
    name = "bch-toggle-window",
    -- key_sequence is interpreted by PHYSICAL key position, always named after
    -- the QWERTY layout. On AZERTY, "W" is the key labelled Z and "A" the key
    -- labelled Q, so those letters land somewhere else than they read.
    --
    -- N sits in the same physical spot on both layouts, and ALT + N is unused by
    -- vanilla and by every mod in this install. Rebindable in
    -- Options -> Controls -> Mods.
    key_sequence = "ALT + N",
    consuming = "none",
  },
  {
    type = "shortcut",
    name = "bch-toggle-window",
    order = "z[belt-capacity]",
    action = "lua",
    associated_control_input = "bch-toggle-window",
    toggleable = true,
    icon = "__BeltCapacityHelper__/graphics/belt-capacity-x56.png",
    icon_size = 56,
    small_icon = "__BeltCapacityHelper__/graphics/belt-capacity-x24.png",
    small_icon_size = 24,
  },
})
