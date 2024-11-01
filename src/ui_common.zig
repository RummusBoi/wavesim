const Coordinate = @import("common.zig").Coordinate;
const HoverState = @import("window.zig").HoverState;
const Simstate = @import("simstate.zig").Simstate;
const Appstate = @import("appstate.zig").Appstate;
const std = @import("std");
const camera_to_sim_coord = @import("window.zig").camera_to_sim_coord;
fn intersects(point: Coordinate, x: i32, y: i32, w: i32, h: i32) bool {
    return point.x < x + w and point.x > x and point.y < y + h and point.y > y;
}

pub const Box = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    styling: BoxStyling,

    pub fn init(x: i32, y: i32, width: i32, height: i32, non_hover: BoxStyling, hover: ?BoxStyling, pressed: ?BoxStyling, mouse_pos: Coordinate, is_holding_left_button: bool) Box {
        const styling = switch (HoverState.from_bool(intersects(mouse_pos, x, y, width, height), is_holding_left_button)) {
            .None => non_hover,
            .Hover => hover orelse non_hover,
            .Pressed => pressed orelse hover orelse non_hover,
        };
        return Box{ .x = x, .y = y, .width = width, .height = height, .styling = styling };
    }
};

pub const BoxStyling = struct {
    fill_color: ?Color,
    border: ?struct {
        color: Color,
        width: u32,
    } = null,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Button = struct {
    payload: [16]u8 = undefined,
    on_click_inner: *const fn (self: *Button, _: *Simstate, appstate: *Appstate) void,
    on_mouse_drag_inner: *const fn (self: *Button, _: *Simstate, appstate: *Appstate, window_width: i32, window_height: i32, xrel: i32, yrel: i32) void,
    box: Box,
    pub fn on_click(self: *Button, simstate: *Simstate, appstate: *Appstate) void {
        (self.on_click_inner)(self, simstate, appstate);
    }
    pub fn on_mouse_drag(self: *Button, simstate: *Simstate, appstate: *Appstate, window_width: i32, window_height: i32, xrel: i32, yrel: i32) void {
        (self.on_mouse_drag_inner)(self, simstate, appstate, window_width, window_height, xrel, yrel);
    }
};

pub const ObstacleButton = struct {
    box: Box,
    id: u32,
    draw_start_pos: ?Coordinate,

    pub fn init(id: u32, box: Box) Button {
        var payload: [16]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], id, .big);

        return Button{
            .box = box,
            .on_click_inner = on_click,
            .on_mouse_drag_inner = on_mouse_drag,
            .payload = payload,
        };
    }

    pub fn on_click(btn: *Button, _: *Simstate, appstate: *Appstate) void {
        const id = std.mem.readInt(u32, btn.payload[0..4], .big);
        appstate.drag_obstacle_id = id;

        appstate.selected_entity = id;
    }

    pub fn on_mouse_drag(btn: *Button, simstate: *Simstate, appstate: *Appstate, window_width: i32, window_height: i32, xrel: i32, yrel: i32) void {
        const id = std.mem.readInt(u32, btn.payload[0..4], .big);

        if (simstate.get_obstacle_by_id(id)) |obstacle| {
            const sim_drag_start = camera_to_sim_coord(appstate.zoom_level, appstate.window_pos, .{ .width = window_width, .height = window_height }, .{ .x = @intCast(appstate.mouse_pos.x), .y = @intCast(appstate.mouse_pos.y) });
            const sim_drag_end = camera_to_sim_coord(appstate.zoom_level, appstate.window_pos, .{ .width = window_width, .height = window_height }, .{ .x = @intCast(appstate.mouse_pos.x + xrel), .y = @intCast(appstate.mouse_pos.y + yrel) });
            const sim_drag_delta = sim_drag_end.sub(sim_drag_start);

            obstacle.x = @intCast(@as(i32, @intCast(obstacle.x)) + @as(i32, @intCast(sim_drag_delta.x)));
            obstacle.y = @intCast(@as(i32, @intCast(obstacle.y)) + @as(i32, @intCast(sim_drag_delta.y)));

            appstate.updates.simstate = true;
        }
    }
};
