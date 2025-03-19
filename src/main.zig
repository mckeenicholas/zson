const std = @import("std");
const zson = @import("root.zig");

pub fn main() !void {
    // Example usage of the zson library
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse a JSON string
    const json_str =
        \\{
        \\  "name": "ZSON",
        \\  "version": "1.0.0",
        \\  "description": "A simple JSON library for Zig"
        \\}
    ;

    var value = try zson.parse(allocator, json_str);
    defer value.deinit();

    // Print the parsed JSON with nice formatting
    const stdout = std.io.getStdOut().writer();
    try value.print(stdout);
}
