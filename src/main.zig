const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const m = std.math;
const RndGen = std.Random.DefaultPrng;

const Pos = rl.Vector2;
const p = rl.Vector2.init;

const screenWidth = 1200;
const screenHeight = 1000;

// Number of cells per dimension in grid
const GRID_SIZE: u32 = 100;
// Default pixels per grid square
const GRID_CELL: u32 = 40;
const GRID_LINE: u32 = 4;
// Max portion of screen size to show outside of grid on pan
const CLAMP: f32 = 0.05;

const CellState = enum {
    live,
    will_live,
    will_die,
    dead,

    pub fn isAlive(self: CellState) bool {
        switch (self) {
            .live, .will_die => return true,
            else => return false,
        }
    }
    pub fn flipped(self: CellState) CellState {
        if (self.isAlive()) return .dead else return .live;
    }
};

/// Represents a coordinate in the grid
const CellPos = struct {
    x: usize,
    y: usize,

    pub fn init(x: usize, y: usize) CellPos {
        return CellPos{
            .x = x,
            .y = y,
        };
    }
};

const Grid = struct {
    grid: [GRID_SIZE][GRID_SIZE]CellState,
    /// Keeps track of active cell during drag drawing
    last_toggle: CellPos = undefined,

    pub fn init() Grid {
        return Grid{
            .grid = [_][GRID_SIZE]CellState{[_]CellState{.dead} ** GRID_SIZE} ** GRID_SIZE,
        };
    }

    /// Init to random live cells
    pub fn rand(self: *Grid) !void {
        var rnd = RndGen.init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        for (0..self.grid.len) |i| {
            for (0..self.grid[i].len) |j| {
                if (rnd.random().int(u8) % 5 == 0) {
                    self.grid[i][j] = .live;
                }
            }
        }
    }

    pub fn clear(self: *Grid) void {
        for (0..self.grid.len) |i| {
            for (0..self.grid[i].len) |j| {
                    self.grid[i][j] = .dead;
            }
        }
    }

    pub fn draw(self: *Grid) void {
        const end = (GRID_LINE + GRID_CELL) * GRID_SIZE;

        // Vertical
        for (0..GRID_SIZE + 1) |iu| {
            const i: f32 = @floatFromInt(iu);
            const x = i * GRID_CELL + i * GRID_LINE; // account for lines between cells
            rl.drawLineEx(p(x, 0), p(x, end), GRID_LINE, FAINT);
        }

        // Horizontal
        for (0..GRID_SIZE + 1) |iu| {
            const i: f32 = @floatFromInt(iu);
            const y = i * GRID_CELL + i * GRID_LINE; // account for lines between cells
            rl.drawLineEx(p(0, y), p(end, y), GRID_LINE, FAINT);
        }

        // Fill
        for (0..GRID_SIZE) |iu| {
            const i: i32 = @intCast(iu);
            const x = i * (GRID_CELL + GRID_LINE) + GRID_LINE / 2;
            for (0..GRID_SIZE) |ju| {
                const j: i32 = @intCast(ju);
                const y = j * (GRID_CELL + GRID_LINE) + GRID_LINE / 2;
                if (self.grid[iu][ju].isAlive()) {
                    const color = switch (self.grid[iu][ju]) {
                        CellState.live => FILL,
                        CellState.will_die => FILL_DARK,
                        else => ERROR,
                    };
                    rl.drawRectangle(x, y, GRID_CELL, GRID_CELL, color);
                }
            }
        }
    }

    pub fn step(self: *Grid) void {
        for (0..GRID_SIZE) |i| {
            for (0..GRID_SIZE) |j| {
                if (self.grid[i][j] == CellState.live) {
                    const nbrs = self.getNeighbours(i, j);
                    if (nbrs < 2 or nbrs > 3) {
                        self.grid[i][j] = CellState.will_die;
                    }
                } else if (self.grid[i][j] == CellState.dead) {
                    const nbrs = self.getNeighbours(i, j);
                    if (nbrs == 3) self.grid[i][j] = CellState.will_live;
                }
            }
        }
        for (0..GRID_SIZE) |i| {
            for (0..GRID_SIZE) |j| {
                switch (self.grid[i][j]) {
                    CellState.will_die => self.grid[i][j] = CellState.dead,
                    CellState.will_live => self.grid[i][j] = CellState.live,
                    else => continue,
                }
            }
        }
    }

    fn getNeighbours(self: *Grid, x: usize, y: usize) u32 {
        const x_start = if (x == 0) 0 else x - 1;
        const y_start = if (y == 0) 0 else y - 1;
        // No inclusive ranges :/
        const x_end = @min(x + 2, GRID_SIZE);
        const y_end = @min(y + 2, GRID_SIZE);

        // std.debug.print("x:{} y:{}", .{ x, y });
        // std.debug.print(" xs:{} ys:{}", .{ x_start, y_start });
        // std.debug.print(" xe:{} ye:{}", .{ x_end, y_end });

        var count: u32 = 0;
        for (x_start..x_end) |xi| {
            for (y_start..y_end) |yi| {
                if (self.grid[xi][yi].isAlive()) {
                    count += 1;
                }
            }
        }
        // std.debug.print(" count:{}\n", .{count});
        // Account for own cell counted
        if (self.grid[x][y].isAlive()) {
            return count - 1;
        }
        return count;
    }

    const Drag = enum {
        press,
        drag,
    };

    /// Takes in worldspace position
    pub fn toggle(self: *Grid, pos: Pos, drag: Drag) void {
        const x = pos.x / (GRID_CELL + GRID_LINE);
        const y = pos.y / (GRID_CELL + GRID_LINE);

        if (x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE) {
            return;
        }
        const x_cell: usize = @intFromFloat(x);
        const y_cell: usize = @intFromFloat(y);
        if (drag == .drag and x_cell == self.last_toggle.x and y_cell == self.last_toggle.y) {
            return;
        }
        self.grid[x_cell][y_cell] = self.grid[x_cell][y_cell].flipped();
        self.last_toggle = CellPos.init(x_cell, y_cell);
    }
};

const FAINT = rl.Color.init(66, 69, 73, 0xFF);
const BG = rl.Color.init(0x1A, 0x1A, 0x2B, 0xFF);
const FILL = rl.Color.init(0xFF, 0x63, 0xA2, 0xFF);
const FILL_DARK = rl.Color.init(247, 177, 64, 0xFF);
const ERROR = rl.Color.init(181, 53, 108, 0xFF);

pub fn main() anyerror!void {
    var cam = rl.Camera2D{
        .target = p((GRID_CELL + GRID_LINE) * GRID_SIZE / 2, (GRID_CELL + GRID_LINE) * GRID_SIZE / 2),
        .offset = p(screenWidth / 2, screenHeight / 2),
        .rotation = 0,
        .zoom = 0.5,
    };

    const grid_size = (GRID_CELL + GRID_LINE) * GRID_SIZE;
    var grid = Grid.init();
    var mouse_pos = rl.getMousePosition();

    rl.initWindow(screenWidth, screenHeight, "Game of Life");
    defer rl.closeWindow();

    rl.setTargetFPS(60);
    rg.guiLoadStyle("themes/style_lavanda.rgs");
    rg.guiSetIconScale(2);

    var rand = true;
    var clear = false;
    var paused = false;
    var step_timer: f32 = 0;
    while (!rl.windowShouldClose()) {
        // Run step every 100ms
        step_timer += rl.getFrameTime();
        if (step_timer >= 0.1 and !paused) {
            grid.step();
            step_timer = 0;
        }
        // Randomize if required
        if (rand) {
            try grid.rand();
            rand = false;
        }
        // Clear if required
        if (clear) {
            grid.clear();
            clear = false;
        }
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(BG);

        if (rl.isMouseButtonDown(.mouse_button_left)) {
            cam.target = rl.getScreenToWorld2D(cam.offset.subtract(rl.getMouseDelta()), cam);
            mouse_pos = rl.getMousePosition();
        }

        if (rl.isMouseButtonPressed(.mouse_button_right)) {
            grid.toggle(rl.getScreenToWorld2D(rl.getMousePosition(), cam), .press);
        } else if (rl.isMouseButtonDown(.mouse_button_right)) {
            grid.toggle(rl.getScreenToWorld2D(rl.getMousePosition(), cam), .drag);
        }

        if (rl.isKeyPressed(.key_p)) {
            paused = !paused;
        }

        const scroll = rl.getMouseWheelMove();
        if (scroll != 0) {
            const worldMouse = rl.getScreenToWorld2D(rl.getMousePosition(), cam);
            cam.offset = rl.getMousePosition();
            cam.target = worldMouse;
            cam.zoom = @max(cam.zoom + scroll * 0.05, 0.25);
        }

        // Lock camera
        // TODO: Will break if screen is too wide
        const clamp_dist = CLAMP * (1 / cam.zoom);
        const cam_xmin_limit = -(screenWidth * clamp_dist);
        const cam_xmin_clamp = cam_xmin_limit + (cam.offset.x / cam.zoom);
        const cam_xmax_limit = grid_size + screenWidth * clamp_dist;
        const cam_xmax_clamp = cam_xmax_limit - ((screenWidth - cam.offset.x) / cam.zoom);
        cam.target.x = m.clamp(cam.target.x, cam_xmin_clamp, cam_xmax_clamp);
        const cam_ymin_limit = -(screenHeight * clamp_dist);
        const cam_ymin_clamp = cam_ymin_limit + (cam.offset.y / cam.zoom);
        const cam_ymax_limit = grid_size + screenHeight * clamp_dist;
        const cam_ymax_clamp = cam_ymax_limit - ((screenHeight - cam.offset.y) / cam.zoom);
        cam.target.y = m.clamp(cam.target.y, cam_ymin_clamp, cam_ymax_clamp);

        // Draw worldspace
        {
            cam.begin();
            defer cam.end();

            grid.draw();
        }

        // rl.drawCircleV(cam.offset, 10, rl.Color.green);
        if (rg.guiButton(rl.Rectangle.init(25, 25, 50, 50), rg.guiIconText(132, "")) == 1) paused = !paused;
        if (rg.guiButton(rl.Rectangle.init(25 + 70, 25, 50, 50), rg.guiIconText(211, "")) == 1) rand = true;
        if (rg.guiButton(rl.Rectangle.init(25 + 140, 25, 50, 50), rg.guiIconText(9, "")) == 1) clear = true;
    }
}
