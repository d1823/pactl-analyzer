const std = @import("std");

pub const SinkId = struct {
    value: []const u8,

    pub fn eql(self: SinkId, other: SinkId) bool {
        return std.mem.eql(u8, self.value, other.value);
    }
};

pub const Sink = struct {
    id: SinkId, volume: u8, muted: bool
};

pub fn get_default_sink_id(buffer: []u8) error{NoDefaultSink}!SinkId {
    var it = std.mem.split(buffer, "\n");
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, "Default Sink:")) {
            return SinkId{ .value = line[14..] };
        }
    }

    return error.NoDefaultSink;
}

// TODO: Parsing is done by stepping over lines, not looking after correct headers.
//       It's quite possible, that once pactl changes it's output, this program will no longer work as intended.
//       It might be better to rewrite it to parse after headers.
pub fn get_all_sinks(allocator: *std.mem.Allocator, buffer: []u8) anyerror!std.ArrayList(Sink) {
    var list = std.ArrayList(Sink).init(allocator);

    var it = std.mem.split(buffer, "\n");
    while (it.next()) |line| {
        const sinkHeader = std.mem.trim(u8, line, " \t");

        if (!std.mem.startsWith(u8, sinkHeader, "Sink #")) {
            continue;
        }

        _ = it.next(); // Skip over State
        const idLine = std.mem.trim(u8, it.next() orelse unreachable, " \t");

        _ = it.next(); // Skip over Description
        _ = it.next(); // Skip over Driver
        _ = it.next(); // Skip over Sample Specification
        _ = it.next(); // Skip over Channel Map
        _ = it.next(); // Skip over Owner Module

        const muteLine = std.mem.trim(u8, it.next() orelse unreachable, " \t");
        var volumeLineParts = std.mem.tokenize(it.next() orelse unreachable, " \t");
        const volumeDigit = while (volumeLineParts.next()) |part| {
            if (std.mem.endsWith(u8, part, "%")) {
                break std.mem.trimRight(u8, part, "%");
            }
        } else unreachable;

        try list.append(Sink{
            .id = SinkId{ .value = idLine[6..] },
            .volume = try std.fmt.parseInt(u8, volumeDigit, 10),
            .muted = std.mem.eql(u8, muteLine, "Mute: yes"),
        });

        continue;
    }

    return list;
}

pub fn get_sink(sinks: std.ArrayList(Sink), sink_id: SinkId) ?Sink {
    for (sinks.items) |current_sink| {
        if (sink_id.eql(current_sink.id)) {
            return current_sink;
        }
    }

    return null;
}
