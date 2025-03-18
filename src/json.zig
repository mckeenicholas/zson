const std = @import("std");
const parser = @import("parser.zig");

pub const JsonValueType = enum {
    Null,
    Boolean,
    Number,
    String,
    Array,
    Object,
};

pub const JsonValue = struct {
    const Self = @This();

    data: union(JsonValueType) {
        Null: void,
        Boolean: bool,
        Number: f64,
        String: []const u8,
        Array: std.ArrayList(JsonValue),
        Object: std.StringHashMap(JsonValue),
    },

    allocator: std.mem.Allocator,

    pub fn @"null"(allocator: std.mem.Allocator) Self {
        return .{
            .data = .{ .Null = {} },
            .allocator = allocator,
        };
    }

    pub fn boolean(allocator: std.mem.Allocator, value: bool) Self {
        return .{
            .data = .{ .Boolean = value },
            .allocator = allocator,
        };
    }

    pub fn number(allocator: std.mem.Allocator, value: f64) Self {
        return .{
            .data = .{ .Number = value },
            .allocator = allocator,
        };
    }

    pub fn string(allocator: std.mem.Allocator, value: []const u8) !Self {
        const str = try allocator.dupe(u8, value);
        return .{
            .data = .{ .String = str },
            .allocator = allocator,
        };
    }

    pub fn array(allocator: std.mem.Allocator) !Self {
        return .{
            .data = .{ .Array = std.ArrayList(JsonValue).init(allocator) },
            .allocator = allocator,
        };
    }

    pub fn object(allocator: std.mem.Allocator) !Self {
        return .{
            .data = .{ .Object = std.StringHashMap(JsonValue).init(allocator) },
            .allocator = allocator,
        };
    }

    pub fn put(self: *Self, key: []const u8, value: JsonValue) !void {
        switch (self.data) {
            .Object => |*obj| {
                const key_owned = try self.allocator.dupe(u8, key);
                try obj.put(key_owned, value);
            },
            else => return error.NotAnObject,
        }
    }

    pub fn append(self: *Self, value: JsonValue) !void {
        switch (self.data) {
            .Array => |*arr| {
                try arr.append(value);
            },
            else => return error.NotAnArray,
        }
    }

    pub fn deinit(self: *Self) void {
        switch (self.data) {
            .String => |str| {
                self.allocator.free(str);
            },
            .Array => |arr| {
                for (arr.items) |*value| {
                    value.deinit();
                }
                arr.deinit();
            },
            .Object => |*obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    var value = entry.value_ptr.*;
                    value.deinit();
                }
                obj.deinit();
            },
            else => {},
        }
    }

    pub fn parse(allocator: std.mem.Allocator, input: []const u8) !JsonValue {
        var parseObject = parser.new(allocator, input);
        return try parseObject.parseValue();
    }

    pub fn dump(self: Self, writer: anytype) !void {
        switch (self.data) {
            .Null => try writer.writeAll("null"),
            .Boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .Number => |n| try writer.print("{d}", .{n}),
            .String => |s| try writer.print("\"{s}\"", .{s}),
            .Array => |arr| {
                try writer.writeByte('[');
                for (arr.items, 0..) |item, i| {
                    try item.dump(writer);
                    if (i < arr.items.len - 1) {
                        try writer.writeByte(',');
                    }
                }
                try writer.writeByte(']');
            },
            .Object => |obj| {
                try writer.writeByte('{');
                var it = obj.iterator();
                var i: usize = 0;
                while (it.next()) |entry| : (i += 1) {
                    try writer.writeByte('"');
                    try writer.writeAll(entry.key_ptr.*);
                    try writer.writeAll("\":");
                    try entry.value_ptr.*.dump(writer);
                    if (i < obj.count() - 1) {
                        try writer.writeByte(',');
                    }
                }
                try writer.writeByte('}');
            },
        }
    }

    fn _print(self: Self, writer: anytype, indent_level: usize) !void {
        switch (self.data) {
            .Null => try writer.writeAll("null"),
            .Boolean => |b| try writer.writeAll(if (b) "true" else "false"),
            .Number => |n| try writer.print("{d}", .{n}),
            .String => |s| try writer.print("\"{s}\"", .{s}),
            .Array => |arr| {
                try writer.writeByte('[');
                if (arr.items.len > 0) {
                    try writer.writeByte('\n');
                    for (arr.items, 0..) |item, i| {
                        try writer.writeByteNTimes(' ', (indent_level + 1) * 2);
                        try item._print(writer, indent_level + 1);
                        if (i < arr.items.len - 1) {
                            try writer.writeAll(",\n");
                        }
                    }
                    try writer.writeByte('\n');
                    try writer.writeByteNTimes(' ', indent_level * 2);
                }
                try writer.writeByte(']');
            },
            .Object => |obj| {
                try writer.writeByte('{');
                var it = obj.iterator();
                var i: usize = 0;
                if (obj.count() > 0) {
                    try writer.writeByte('\n');
                    while (it.next()) |entry| : (i += 1) {
                        try writer.writeByteNTimes(' ', (indent_level + 1) * 2);
                        try writer.writeByte('"');
                        try writer.writeAll(entry.key_ptr.*);
                        try writer.writeAll("\": ");
                        try entry.value_ptr.*._print(writer, indent_level + 1);
                        if (i < obj.count() - 1) {
                            try writer.writeAll(",\n");
                        }
                    }
                    try writer.writeByte('\n');
                    try writer.writeByteNTimes(' ', indent_level * 2);
                }
                try writer.writeByte('}');
            },
        }
    }

    pub fn print(self: Self, writer: anytype) !void {
        try self._print(writer, 0);
        try writer.writeByte('\n');
    }

    pub const GetError = error{
        WrongType,
        KeyNotFound,
        IndexOutOfBounds,
    };

    pub fn isNull(self: Self) bool {
        return self.data == .Null;
    }

    pub fn isBoolean(self: Self) bool {
        return self.data == .Boolean;
    }

    pub fn isNumber(self: Self) bool {
        return self.data == .Number;
    }

    pub fn isString(self: Self) bool {
        return self.data == .String;
    }

    pub fn isArray(self: Self) bool {
        return self.data == .Array;
    }

    pub fn isObject(self: Self) bool {
        return self.data == .Object;
    }

    pub fn getBool(self: Self) GetError!bool {
        if (self.data != .Boolean) return error.WrongType;
        return self.data.Boolean;
    }

    pub fn getNumber(self: Self) GetError!f64 {
        if (self.data != .Number) return error.WrongType;
        return self.data.Number;
    }

    pub fn getString(self: Self) GetError![]const u8 {
        if (self.data != .String) return error.WrongType;
        return self.data.String;
    }

    pub fn getIndex(self: Self, index: usize) GetError!JsonValue {
        if (self.data != .Array) return error.WrongType;
        if (index >= self.data.Array.items.len) return error.IndexOutOfBounds;
        return self.data.Array.items[index];
    }

    pub fn getField(self: Self, key: []const u8) GetError!JsonValue {
        if (self.data != .Object) return error.WrongType;
        return self.data.Object.get(key) orelse error.KeyNotFound;
    }

    pub fn getFields(self: Self) GetError!std.StringHashMap(JsonValue) {
        if (self.data != .Object) return error.WrongType;
        return self.data.Object;
    }

    pub fn length(self: Self) GetError!usize {
        return switch (self.data) {
            .Array => |arr| arr.items.len,
            .Object => |obj| obj.count(),
            else => error.WrongType,
        };
    }

    pub const ToStructError = error{
        RequiredFieldMissing,
        WrongType,
        KeyNotFound,
    } || GetError;

    pub fn toStruct(self: Self, comptime T: type) ToStructError!T {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                if (self.data != .Object) return error.WrongType;
                var result: T = undefined;

                inline for (info.fields) |field| {
                    const field_type = field.type;
                    const field_name = field.name;

                    // Check if field is optional
                    const is_optional = @typeInfo(field_type) == .optional;

                    // Get the field value
                    const maybe_value: ?JsonValue = if (is_optional) blk: {
                        const field_value = self.getField(field_name) catch |err| switch (err) {
                            error.KeyNotFound => {
                                @field(result, field_name) = null;
                                break :blk null;
                            },
                            else => |e| return e,
                        };
                        if (field_value.isNull()) {
                            @field(result, field_name) = null;
                            break :blk null;
                        }
                        break :blk field_value;
                    } else self.getField(field_name) catch |err| switch (err) {
                        error.KeyNotFound => return error.RequiredFieldMissing,
                        else => |e| return e,
                    };

                    if (maybe_value != null) {
                        const value = maybe_value orelse unreachable;

                        const actual_type = if (is_optional)
                            @typeInfo(field_type).optional.child
                        else
                            field_type;

                        @field(result, field_name) = switch (@typeInfo(actual_type)) {
                            .int => blk: {
                                const num = try value.getNumber();
                                if (@mod(num, 1) != 0) {
                                    std.debug.print("Warning: Converting non-integer {d} to integer\n", .{num});
                                }
                                break :blk @intFromFloat(num);
                            },
                            .float => try value.getNumber(),
                            .bool => try value.getBool(),
                            .@"struct" => try value.toStruct(actual_type),
                            .array => |arr_info| blk: {
                                if (!value.isArray()) return error.WrongType;
                                var arr: actual_type = undefined;
                                const len = try value.length();
                                if (len > arr_info.len) return error.WrongType;
                                for (0..len) |i| {
                                    const item = try value.getIndex(i);
                                    arr[i] = try item.toStruct(arr_info.child);
                                }
                                break :blk arr;
                            },
                            .pointer => |ptr_info| switch (ptr_info.size) {
                                .slice => if (ptr_info.child == u8) blk: {
                                    break :blk try value.getString();
                                } else {
                                    return error.WrongType;
                                },
                                else => return error.WrongType,
                            },
                            else => return error.WrongType,
                        };
                    }
                }
                return result;
            },
            // TODO: Add StringHashMap as valid entry for type.
            .int => {
                const num = try self.getNumber();

                if (@mod(num, 1) != 0) {
                    std.debug.print("Warning: Converting non-integer {d} to integer\n", .{num});
                }

                return @intFromFloat(num);
            },
            .float => return try self.getNumber(),
            .bool => return try self.getBool(),
            .pointer => |ptr_info| switch (ptr_info.size) {
                .slice => if (ptr_info.child == u8) {
                    return try self.getString();
                } else {
                    return error.WrongType;
                },
                else => return error.WrongType,
            },
            else => return error.WrongType,
        }
    }

    pub fn toJsonValue(comptime T: type, value: T, allocator: std.mem.Allocator) !JsonValue {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                var json_obj = try JsonValue.object(allocator);
                inline for (info.fields) |field| {
                    const field_name = field.name;
                    const field_value = @field(value, field_name);
                    const field_type = field.type;

                    const json_field_value = try toJsonValue(field_type, field_value, allocator);
                    try json_obj.put(field_name, json_field_value);
                }
                return json_obj;
            },
            .int => return JsonValue.number(allocator, @floatFromInt(value)),
            .float => return JsonValue.number(allocator, value),
            .bool => return JsonValue.boolean(allocator, value),
            .pointer => |ptr_info| switch (ptr_info.size) {
                .slice => if (ptr_info.child == u8) {
                    return JsonValue.string(allocator, value);
                } else {
                    return error.WrongType;
                },
                else => return error.WrongType,
            },
            .optional => {
                if (value == null) {
                    return JsonValue.null(allocator);
                }

                const inner_type = @typeInfo(T).optional.child;
                return toJsonValue(inner_type, value.?, allocator);
            },
            else => return error.WrongType,
        }
    }
};
