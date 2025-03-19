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

    pub fn objectWithCapacity(allocator: std.mem.Allocator, capacity: u32) !Self {
        var map = std.StringHashMap(JsonValue).init(allocator);
        try map.ensureTotalCapacity(capacity);
        return .{
            .data = .{ .Object = map },
            .allocator = allocator,
        };
    }

    pub fn arrayWithCapacity(allocator: std.mem.Allocator, capacity: u32) !Self {
        return .{
            .data = .{ .Array = try std.ArrayList(JsonValue).initCapacity(allocator, capacity) },
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

    pub fn deepCopy(self: Self) !Self {
        return try self.deepCopyWithAllocator(self.allocator);
    }

    pub fn deepCopyWithAllocator(self: Self, new_allocator: std.mem.Allocator) !Self {
        return switch (self.data) {
            .Null => JsonValue.null(new_allocator),
            .Boolean => |b| JsonValue.boolean(new_allocator, b),
            .Number => |n| JsonValue.number(new_allocator, n),
            .String => |s| try JsonValue.string(new_allocator, s),
            .Array => |arr| blk: {
                var new_arr = try JsonValue.array(new_allocator);
                for (arr.items) |item| {
                    const item_copy = try item.deepCopyWithAllocator(new_allocator);
                    try new_arr.append(item_copy);
                }
                break :blk new_arr;
            },
            .Object => |obj| blk: {
                var new_obj = try JsonValue.object(new_allocator);
                var it = obj.iterator();
                while (it.next()) |entry| {
                    const value_copy = try entry.value_ptr.*.deepCopyWithAllocator(new_allocator);
                    try new_obj.put(entry.key_ptr.*, value_copy);
                }
                break :blk new_obj;
            },
        };
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

    pub fn parseEnum(self: Self, comptime T: enum {}) !T {
        if (!self.isString()) return error.WrongType;
        const str = try self.getString();

        inline for (@typeInfo(T).Enum.fields) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @intFromEnum(T);
            }
        }

        return error.KeyNotFound;
    }

    pub fn toStruct(self: Self, comptime T: type) ToStructError!T {
        return switch (@typeInfo(T)) {
            .@"struct" => blk_struct: {
                if (T == JsonValue) {
                    return try T.deepCopy();
                }

                const info = @typeInfo(T).@"struct";
                if (@hasDecl(T, "KV") and info.fields.len >= 2) {
                    const is_hash_map = @hasField(T, "hash_map") or
                        std.mem.indexOf(u8, @typeName(T), "StringHashMap") != null;
                    if (is_hash_map and self.data == .Object) {
                        // Extract value type from StringHashMap
                        const value_type = @typeInfo(info.fields[1].type).Pointer.child;

                        var result = T.init(self.allocator);
                        var it = self.data.Object.iterator();
                        while (it.next()) |entry| {
                            const key_owned = try self.allocator.dupe(u8, entry.key_ptr.*);
                            const value = try entry.value_ptr.*.toStruct(value_type);
                            try result.put(key_owned, value);
                        }
                        return result;
                    }
                }

                if (self.data != .Object) return error.WrongType;
                var result: T = undefined;

                inline for (@typeInfo(T).@"struct".fields) |field| {
                    const field_name = field.name;
                    const field_type = field.type;
                    const is_optional = @typeInfo(field_type) == .optional;

                    // Handle optional fields
                    if (is_optional) {
                        // Try to get field, set to null if missing or null in JSON
                        const maybe_value: ?JsonValue = self.getField(field_name) catch |err| switch (err) {
                            error.KeyNotFound => null,
                            else => |e| return e,
                        };

                        @field(result, field_name) = if (maybe_value != null and !maybe_value.?.isNull()) blk_eval_optional: {
                            const field_value = maybe_value orelse unreachable;
                            // Extract the child type from the optional
                            const child_type = @typeInfo(field_type).optional.child;

                            // Recursively convert the value
                            break :blk_eval_optional try field_value.toStruct(child_type);
                        } else null;
                    }
                    // Handle required fields
                    else {
                        const field_value = self.getField(field_name) catch |err| switch (err) {
                            error.KeyNotFound => return error.RequiredFieldMissing,
                            else => |e| return e,
                        };

                        // Recursively convert the value
                        @field(result, field_name) = try field_value.toStruct(field_type);
                    }
                }
                break :blk_struct result;
            },
            .int => blk: {
                const num = try self.getNumber();
                if (@mod(num, 1) != 0) {
                    std.debug.print("Warning: Converting non-integer {d} to integer\n", .{num});
                }
                break :blk @intFromFloat(num);
            },
            .float => try self.getNumber(),
            .bool => try self.getBool(),
            .array => |arr_info| blk: {
                if (!self.isArray()) return error.WrongType;
                var arr: T = undefined;
                const len = try self.length();
                if (len > arr_info.len) return error.WrongType;

                for (0..len) |i| {
                    const item = try self.getIndex(i);
                    arr[i] = try item.toStruct(arr_info.child);
                }
                break :blk arr;
            },
            .pointer => |ptr_info| switch (ptr_info.size) {
                .slice => if (ptr_info.child == u8) {
                    return try self.getString();
                } else {
                    return error.WrongType;
                },
                else => return error.WrongType,
            },
            else => return error.WrongType,
        };
    }

    pub fn toJsonValue(comptime T: type, value: T, allocator: std.mem.Allocator) !JsonValue {
        switch (@typeInfo(T)) {
            .@"struct" => |info| {
                if (T == JsonValue) {
                    return try T.deepCopy();
                }

                if (@hasDecl(T, "KV") and info.fields.len >= 2) {
                    const is_hash_map = @hasField(T, "hash_map") or
                        std.mem.indexOf(u8, @typeName(T), "StringHashMap") != null;
                    if (is_hash_map) {
                        var json_obj = try JsonValue.object(allocator);

                        // Extract value type from StringHashMap
                        const value_type = @typeInfo(info.fields[1].type).Pointer.child;

                        // Iterate over all keys and values in the hash map
                        var it = value.iterator();
                        while (it.next()) |entry| {
                            const json_field_value = try toJsonValue(value_type, entry.value_ptr.*, allocator);
                            try json_obj.put(entry.key_ptr.*, json_field_value);
                        }
                        return json_obj;
                    }
                }

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
