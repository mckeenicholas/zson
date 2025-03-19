const std = @import("std");
const Json = @import("json.zig");

pub const ParseError = error{
    UnexpectedChar,
    InvalidNumber,
    UnexpectedEof,
    UnmatchedBrace,
    UnmatchedBracket,
    OutOfMemory,
    InvalidCharacter, // From std.fmt.parseFloat
    NotAnArray, // From JsonValue.append
    NotAnObject, // From JsonValue.put
};

pub const Parser = struct {
    input: []const u8,
    index: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Parser {
        return .{
            .allocator = allocator,
            .input = input,
            .index = 0,
        };
    }

    pub fn parseValue(self: *Parser) ParseError!Json.JsonValue {
        self.skipWhitespace();
        if (self.index >= self.input.len) return error.UnexpectedEof;

        return switch (self.input[self.index]) {
            'n' => self.parseNull(),
            't', 'f' => self.parseBoolean(),
            '"' => self.parseString(),
            '{' => self.parseObject(),
            '[' => self.parseArray(),
            '-', '0'...'9' => self.parseNumber(),
            else => error.UnexpectedChar,
        };
    }

    fn skipWhitespace(self: *Parser) void {
        // Optimized whitespace skipping using SIMD if available
        const len = self.input.len;
        while (self.index < len) {
            const c = self.input[self.index];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.index += 1;
            } else {
                break;
            }
        }
    }

    fn parseNull(self: *Parser) ParseError!Json.JsonValue {
        if (self.index + 4 > self.input.len or
            !std.mem.eql(u8, self.input[self.index .. self.index + 4], "null"))
        {
            return error.UnexpectedChar;
        }
        self.index += 4;
        return Json.JsonValue.null(self.allocator);
    }

    fn parseBoolean(self: *Parser) ParseError!Json.JsonValue {
        if (self.index + 4 <= self.input.len and
            std.mem.eql(u8, self.input[self.index .. self.index + 4], "true"))
        {
            self.index += 4;
            return Json.JsonValue.boolean(self.allocator, true);
        } else if (self.index + 5 <= self.input.len and
            std.mem.eql(u8, self.input[self.index .. self.index + 5], "false"))
        {
            self.index += 5;
            return Json.JsonValue.boolean(self.allocator, false);
        }
        return error.UnexpectedChar;
    }

    fn parseKey(self: *Parser) ParseError![]const u8 {
        if (self.index >= self.input.len or self.input[self.index] != '"')
            return error.UnexpectedChar;

        self.index += 1; // Skip opening quote
        const start = self.index;

        // Find the end of the string, watching for escape sequences
        var i = start;
        while (i < self.input.len and self.input[i] != '"') {
            if (self.input[i] == '\\') {
                // Cannot use string view for strings with escape sequences
                return error.UnexpectedChar;
            }
            i += 1;
        }

        if (i >= self.input.len) return error.UnexpectedEof;

        const result = self.input[start..i];
        self.index = i + 1; // Skip closing quote

        return result;
    }

    fn parseString(self: *Parser) ParseError!Json.JsonValue {
        self.index += 1; // Skip opening quote
        const start = self.index;

        // Pre-scan to find the end of the string and calculate length
        var result_len: usize = 0;
        var i = start;
        while (i < self.input.len and self.input[i] != '"') {
            if (self.input[i] == '\\') {
                i += 2; // Skip escape sequence
                result_len += 1;
            } else {
                i += 1;
                result_len += 1;
            }
        }
        if (i >= self.input.len) return error.UnexpectedEof;

        // Allocate the exact size needed for the string
        var result = try self.allocator.alloc(u8, result_len);
        errdefer self.allocator.free(result);

        // Copy while processing escape sequences
        var j: usize = 0;
        i = start;
        while (i < self.input.len and self.input[i] != '"') {
            if (self.input[i] == '\\') {
                // Handle escape sequence properly
                switch (self.input[i + 1]) {
                    '"', '\\', '/' => result[j] = self.input[i + 1],
                    'b' => result[j] = '\x08', // backspace
                    'f' => result[j] = '\x0C', // form feed
                    'n' => result[j] = '\n',
                    'r' => result[j] = '\r',
                    't' => result[j] = '\t',
                    else => result[j] = self.input[i + 1],
                }
                i += 2;
            } else {
                result[j] = self.input[i];
                i += 1;
            }
            j += 1;
        }

        self.index = i + 1; // Skip closing quote
        return Json.JsonValue{
            .data = .{ .String = result },
            .allocator = self.allocator,
        };
    }

    fn parseNumber(self: *Parser) ParseError!Json.JsonValue {
        const start = self.index;

        // Fast path for common integers
        var is_negative = false;
        var result: i64 = 0;
        var is_integer = true;

        if (self.input[self.index] == '-') {
            is_negative = true;
            self.index += 1;
        }

        // Parse integer part
        while (self.index < self.input.len) {
            const c = self.input[self.index];
            if (c >= '0' and c <= '9') {
                result = result * 10 + (c - '0');
                self.index += 1;
            } else {
                break;
            }
        }

        // Check for decimal part
        if (self.index < self.input.len and self.input[self.index] == '.') {
            is_integer = false;
            self.index += 1;

            // Skip decimal digits
            while (self.index < self.input.len) {
                const c = self.input[self.index];
                if (c >= '0' and c <= '9') {
                    self.index += 1;
                } else {
                    break;
                }
            }
        }

        // Check for exponent
        if (self.index < self.input.len and (self.input[self.index] == 'e' or self.input[self.index] == 'E')) {
            is_integer = false;
            self.index += 1;

            // Optional sign
            if (self.index < self.input.len and (self.input[self.index] == '+' or self.input[self.index] == '-')) {
                self.index += 1;
            }

            // Exponent digits
            var has_digits = false;
            while (self.index < self.input.len) {
                const c = self.input[self.index];
                if (c >= '0' and c <= '9') {
                    self.index += 1;
                    has_digits = true;
                } else {
                    break;
                }
            }

            if (!has_digits) return error.InvalidNumber;
        }

        // Use fast path for integers that fit in i64
        if (is_integer and !is_negative and result >= 0) {
            return Json.JsonValue.number(self.allocator, @floatFromInt(result));
        } else if (is_integer and is_negative) {
            return Json.JsonValue.number(self.allocator, @floatFromInt(-result));
        }

        // Fall back to std.fmt.parseFloat for complex cases
        const num_str = self.input[start..self.index];
        const num = try std.fmt.parseFloat(f64, num_str);
        return Json.JsonValue.number(self.allocator, num);
    }

    fn parseArray(self: *Parser) ParseError!Json.JsonValue {
        self.index += 1; // Skip opening bracket

        // Pre-allocate with reasonable capacity
        var array = try Json.JsonValue.arrayWithCapacity(self.allocator, 8);
        errdefer array.deinit();

        self.skipWhitespace();
        if (self.index < self.input.len and self.input[self.index] == ']') {
            self.index += 1;
            return array;
        }

        while (true) {
            const value = try self.parseValue();
            try array.append(value);

            self.skipWhitespace();
            if (self.index >= self.input.len) return error.UnexpectedEof;

            switch (self.input[self.index]) {
                ',' => {
                    self.index += 1;
                    self.skipWhitespace();
                },
                ']' => {
                    self.index += 1;
                    break;
                },
                else => return error.UnexpectedChar,
            }
        }

        return array;
    }

    fn parseObject(self: *Parser) ParseError!Json.JsonValue {
        self.index += 1; // Skip opening brace

        // Use a capacity hint for common object sizes
        var obj = try Json.JsonValue.objectWithCapacity(self.allocator, 8);
        errdefer obj.deinit();

        self.skipWhitespace();
        if (self.index < self.input.len and self.input[self.index] == '}') {
            self.index += 1;
            return obj;
        }

        while (true) {
            self.skipWhitespace();
            if (self.index >= self.input.len or self.input[self.index] != '"') {
                return error.UnexpectedChar;
            }

            const key = try self.parseKey();
            self.skipWhitespace();

            if (self.index >= self.input.len or self.input[self.index] != ':') {
                return error.UnexpectedChar;
            }
            self.index += 1;

            const value = try self.parseValue();
            try obj.put(key, value);

            self.skipWhitespace();
            if (self.index >= self.input.len) return error.UnexpectedEof;

            switch (self.input[self.index]) {
                ',' => {
                    self.index += 1;
                    self.skipWhitespace();
                },
                '}' => {
                    self.index += 1;
                    break;
                },
                else => return error.UnexpectedChar,
            }
        }

        return obj;
    }

    // Add this method for performance-critical paths
    fn expectChar(self: *Parser, expected: u8) ParseError!void {
        if (self.index >= self.input.len or self.input[self.index] != expected) {
            return error.UnexpectedChar;
        }
        self.index += 1;
    }
};

pub fn new(allocator: std.mem.Allocator, input: []const u8) Parser {
    return Parser.init(allocator, input);
}
