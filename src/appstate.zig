const Coordinate = @import("common.zig").Coordinate;
pub const Appstate = struct {
    keep_going: bool = true,
    paused: bool = false,
    window_pos: Coordinate = .{ .x = 0, .y = 0 },
    zoom_level: f32 = 1.0,
    ui_movement_scalor: f32 = 1.0,
    button_states: struct {
        is_holding_up: bool = false,
        is_holding_down: bool = false,
        is_holding_left: bool = false,
        is_holding_right: bool = false,
        is_holding_zoom_in: bool = false,
        is_holding_zoom_out: bool = false,
        is_holding_left_button: bool = false,
    } = .{},

    pub fn init() @This() {
        return Appstate{};
    }
};
