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
        while (self.index < self.input.len and std.ascii.isWhitespace(self.input[self.index])) {
            self.index += 1;
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

    fn parseString(self: *Parser) ParseError!Json.JsonValue {
        self.index += 1; // Skip opening quote
        const start = self.index;
        while (self.index < self.input.len and self.input[self.index] != '"') {
            if (self.input[self.index] == '\\') {
                self.index += 2; // Skip escape sequence
            } else {
                self.index += 1;
            }
        }
        if (self.index >= self.input.len) return error.UnexpectedEof;
        const str = self.input[start..self.index];
        self.index += 1; // Skip closing quote
        return Json.JsonValue.string(self.allocator, str);
    }

    fn parseNumber(self: *Parser) ParseError!Json.JsonValue {
        const start = self.index;
        var has_decimal = false;

        if (self.input[self.index] == '-') self.index += 1;
        while (self.index < self.input.len) : (self.index += 1) {
            const c = self.input[self.index];
            if (c == '.') {
                if (has_decimal) return error.InvalidNumber;
                has_decimal = true;
            } else if (!std.ascii.isDigit(c)) {
                break;
            }
        }

        const num_str = self.input[start..self.index];
        const num = try std.fmt.parseFloat(f64, num_str);
        return Json.JsonValue.number(self.allocator, num);
    }

    fn parseArray(self: *Parser) ParseError!Json.JsonValue {
        self.index += 1; // Skip opening bracket
        var array = try Json.JsonValue.array(self.allocator);
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
        var obj = try Json.JsonValue.object(self.allocator);
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

            var key = try self.parseString();
            self.skipWhitespace();

            if (self.index >= self.input.len or self.input[self.index] != ':') {
                return error.UnexpectedChar;
            }
            self.index += 1;

            const value = try self.parseValue();
            try obj.put(key.data.String, value);
            key.deinit();

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
};

pub fn new(allocator: std.mem.Allocator, input: []const u8) Parser {
    return Parser.init(allocator, input);
}
