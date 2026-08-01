local styles = data.raw["gui-style"]["default"]

--- Lane selector buttons: a pair of icons per ingredient, the active one pressed in.
--- Fixed size so table columns never shift when the selection changes.
--- Single button whose sprite shows the current lane choice. There is no
--- selected variant: the belt picture itself is the state.
styles["bch_lane_button"] = {
  type = "button_style",
  parent = "slot_button",
  size = 34,
  padding = 1,
}

--- Small square − / + used by the per-column stacking stepper.
styles["bch_step_button"] = {
  type = "button_style",
  parent = "button",
  width = 20,
  height = 22,
  padding = 0,
  font = "default-bold",
}

