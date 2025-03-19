//! ZSON - A fast, type-safe JSON library for Zig
//!
//! This library provides a convenient API for working with JSON data in Zig.
//! It supports parsing, manipulation, and serialization and deserialization of JSON values.

const std = @import("std");
const json_internal = @import("json.zig");

pub const Value = json_internal.JsonValue;
pub const ValueType = json_internal.JsonValueType;

pub fn @"null"(allocator: std.mem.Allocator) Value {
    return Value.null(allocator);
}

pub fn boolean(allocator: std.mem.Allocator, value: bool) Value {
    return Value.boolean(allocator, value);
}

pub fn number(allocator: std.mem.Allocator, value: f64) Value {
    return Value.number(allocator, value);
}

pub fn string(allocator: std.mem.Allocator, value: []const u8) !Value {
    return Value.string(allocator, value);
}

pub fn array(allocator: std.mem.Allocator) !Value {
    return Value.array(allocator);
}

pub fn object(allocator: std.mem.Allocator) !Value {
    return Value.object(allocator);
}

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Value {
    return Value.parse(allocator, input);
}

pub fn toStruct(json: Value, comptime T: type) !T {
    return json.toStruct(T);
}

pub fn toJsonValue(comptime T: type, value: T, allocator: std.mem.Allocator) !Value {
    return Value.toJsonValue(T, value, allocator);
}

pub const ParseError = @import("parser.zig").ParseError;
pub const GetError = Value.GetError;
pub const ToStructError = Value.ToStructError;

test {
    std.testing.refAllDeclsRecursive(@This());
}

comptime {
    _ = @import("test.zig");
}
