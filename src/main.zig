const std = @import("std");
const pactl = @import("./pactl.zig");

const ArgsOption = enum {
    Volume, Muted, Status, Help, None
};

const Args = struct {
    option: ArgsOption,
    id: ?pactl.SinkId,

    pub fn init(allocator: *std.mem.Allocator, iterator: *std.process.ArgIterator) anyerror!Args {
        _ = iterator.skip(); // Skip program name

        var option = ArgsOption.None;
        if (iterator.next(allocator)) |given_option| {
            if (std.mem.eql(u8, "volume", given_option catch "")) {
                option = ArgsOption.Volume;
            } else if (std.mem.eql(u8, "muted", given_option catch "")) {
                option = ArgsOption.Muted;
            } else if (std.mem.eql(u8, "status", given_option catch "")) {
                option = ArgsOption.Status;
            }
        }

        var id: ?pactl.SinkId = null;
        if (iterator.next(allocator)) |given_id| {
            const given_id_for_real_now = try given_id;

            id = pactl.SinkId{ .value = given_id_for_real_now };
        }

        return Args{ .option = option, .id = id };
    }
};

const help =
    \\Usage: pactl-analyzer <command> [sink-name]
    \\A simple tool that parses chosen values from the output of `pactl list sinks`.
    \\
    \\Commands:
    \\  help       Prints this message
    \\  volume     Prints the volume formatted as %
    \\  muted      Prints the muted status
    \\  status     Prints the sink status (volume, muted or none)
    \\
    \\
;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(&gpa.allocator);
    defer arena.deinit();

    const args = try Args.init(&arena.allocator, &std.process.args());

    var env_map = try std.process.getEnvMap(&arena.allocator);
    try env_map.set("LANG", "C");

    const info_result = try std.ChildProcess.exec(.{
        .allocator = &arena.allocator,
        .argv = &[_][]const u8{ "pactl", "info" },
        .env_map = &env_map,
    });

    const list_result = try std.ChildProcess.exec(.{
        .allocator = &arena.allocator,
        .argv = &[_][]const u8{ "pactl", "list", "sinks" },
        .env_map = &env_map,
    });

    const sink_id = args.id orelse try pactl.get_default_sink_id(info_result.stdout);
    const sink = pactl.get_sink(try pactl.get_all_sinks(&arena.allocator, list_result.stdout), sink_id);

    const stdout = std.io.getStdOut().writer();

    switch (args.option) {
        ArgsOption.Help => try stdout.print("{}", .{help}),
        ArgsOption.Volume => try stdout.print("{}%\n", .{(sink.?).volume}),
        ArgsOption.Muted => try stdout.print("{}\n", .{(sink.?).muted}),
        ArgsOption.Status => {
            if (sink) |v| {
                if (v.muted) {
                    try stdout.print("MUTED\n", .{});
                } else {
                    try stdout.print("{}%\n", .{(sink.?).volume});
                }
            } else {
                try stdout.print("NONE\n", .{});
            }
        },
        ArgsOption.None => {
            try stdout.print("{}", .{help});
            std.process.exit(1);
        },
    }
}
