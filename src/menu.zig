const Simstate = @import("simstate.zig").Simstate;
const Appstate = @import("appstate.zig").Appstate;
const UI = @import("ui.zig").UI;
const Box = @import("ui_common.zig").Box;
const Button = @import("ui_common.zig").Button;
const sim_to_camera_coord = @import("window.zig").sim_to_camera_coord;
const HEIGHT = @import("window.zig").HEIGHT;
const WIDTH = @import("window.zig").WIDTH;
const Obstacle = @import("common.zig").Obstacle;
pub fn add_menu(_: *Simstate, appstate: *Appstate, ui: *UI, box_index: *usize, button_index: *usize) void {
    if (!appstate.menu_open) {
        return;
    }

    const menu_width = 250;
    ui.boxes[box_index.*] = .{
        .height = HEIGHT,
        .width = menu_width,
        .x = 0,
        .y = 0,
        .styling = .{
            .fill_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        },
    };
    box_index.* += 1;
    // ui.buttons[button_index.*] = .{ .box = .{
    //     .height = 50,
    //     .width = 80,
    //     .x = 10,
    //     .y = 10,
    //     .styling = .{
    //         .fill_color = .{ .r = 50, .g = 50, .b = 50, .a = 255 },
    //     },
    // } };
    // button_index += 1;
    if (appstate.paused) {
        ui.buttons[button_index.*] = PauseButton.init(
            Box.init(
                10,
                10,
                menu_width - 20,
                50,
                .{
                    .fill_color = .{ .r = 8, .g = 153, .b = 46, .a = 255 },
                    .border = null,
                },
                .{
                    .fill_color = .{ .r = 50, .g = 173, .b = 83, .a = 255 },
                    .border = null,
                },
                .{
                    .fill_color = .{ .r = 50, .g = 173, .b = 83, .a = 255 },
                    .border = null,
                },
                appstate.mouse_pos,
                appstate.button_states.is_holding_left_button,
            ),
        );
    } else {
        ui.buttons[button_index.*] = PauseButton.init(
            Box.init(
                10,
                10,
                menu_width - 20,
                50,
                .{
                    .fill_color = .{ .r = 212, .g = 202, .b = 72, .a = 255 },
                    .border = null,
                },
                .{
                    .fill_color = .{ .r = 217, .g = 210, .b = 117, .a = 255 },
                    .border = null,
                },
                .{
                    .fill_color = .{ .r = 217, .g = 210, .b = 117, .a = 255 },
                    .border = null,
                },
                appstate.mouse_pos,
                appstate.button_states.is_holding_left_button,
            ),
        );
    }

    button_index.* += 1;

    ui.buttons[button_index.*] = CreateObstacleButton.init(
        Box.init(
            10,
            70,
            menu_width - 20,
            50,
            .{
                .fill_color = .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            },
            .{
                .fill_color = .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            },
            .{
                .fill_color = .{ .r = 50, .g = 50, .b = 50, .a = 255 },
            },
            appstate.mouse_pos,
            appstate.button_states.is_holding_left_button,
        ),
    );
    button_index.* += 1;
}

pub const PauseButton = struct {
    box: Box,
    pub fn init(box: Box) Button {
        return Button{
            .box = box,
            .on_click_inner = on_click,
            .on_mouse_drag_inner = on_mouse_drag,
            .payload = undefined,
        };
    }
    pub fn on_click(_: *Button, _: *Simstate, appstate: *Appstate) void {
        appstate.paused = !appstate.paused;
    }
    pub fn on_mouse_drag(_: *Button, _: *Simstate, _: *Appstate, _: i32, _: i32) void {}
};

pub const CreateObstacleButton = struct {
    box: Box,
    pub fn init(box: Box) Button {
        return Button{
            .box = box,
            .on_click_inner = on_click,
            .on_mouse_drag_inner = on_mouse_drag,
            .payload = undefined,
        };
    }
    pub fn on_click(_: *Button, simstate: *Simstate, _: *Appstate) void {
        const obs_width = 100;
        const obs_height = 100;
        _ = simstate.create_obstacle(
            @intCast(simstate.width / 2 - obs_width / 2),
            @intCast(simstate.height / 2 - obs_height / 2),
            obs_width,
            obs_height,
        ) catch @panic("Failed to create obstacle");
    }
    pub fn on_mouse_drag(_: *Button, _: *Simstate, _: *Appstate, _: i32, _: i32) void {}
};
