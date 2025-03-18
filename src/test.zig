const std = @import("std");
const Json = @import("json.zig");

test "JsonValue creation and manipulation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test null value
    var null_value = Json.JsonValue.null(allocator);
    defer null_value.deinit();
    try std.testing.expect(null_value.isNull());

    // Test boolean value
    var bool_value = Json.JsonValue.boolean(allocator, true);
    defer bool_value.deinit();
    try std.testing.expect(bool_value.isBoolean());
    try std.testing.expect(try bool_value.getBool() == true);

    // Test number value
    var number_value = Json.JsonValue.number(allocator, 42.0);
    defer number_value.deinit();
    try std.testing.expect(number_value.isNumber());
    try std.testing.expect(try number_value.getNumber() == 42.0);

    // Test string value
    const test_str = "hello";
    var string_value = try Json.JsonValue.string(allocator, test_str);
    defer string_value.deinit();
    try std.testing.expect(string_value.isString());
    try std.testing.expect(std.mem.eql(u8, try string_value.getString(), test_str));

    // Test array value
    var array_value = try Json.JsonValue.array(allocator);
    defer array_value.deinit();
    {
        const num_for_array = Json.JsonValue.number(allocator, 42.0);
        try array_value.append(num_for_array);
    }
    try std.testing.expect(array_value.isArray());
    try std.testing.expect(try array_value.length() == 1);
    const array_item = try array_value.getIndex(0);
    try std.testing.expect(try array_item.getNumber() == 42.0);

    // Test object value
    var object_value = try Json.JsonValue.object(allocator);
    defer object_value.deinit();
    {
        const str_for_obj = try Json.JsonValue.string(allocator, test_str);
        try object_value.put("key", str_for_obj);
    }
    try std.testing.expect(object_value.isObject());
    const obj_value = try object_value.getField("key");
    try std.testing.expect(std.mem.eql(u8, try obj_value.getString(), test_str));
}

test "JsonValue toStruct and toJsonValue" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const Address = struct {
        street: []const u8,
        city: []const u8,
        zip: ?i32,
    };

    const Person = struct {
        name: []const u8,
        age: ?i32,
        addr: Address,
    };

    const json_str =
        \\{
        \\  "name": "John Doe",
        \\  "age": null,
        \\  "addr": {
        \\    "street": "9641 W Sunset Blvd",
        \\    "city": "Beverly Hills",
        \\    "zip": 90210
        \\  }
        \\}
    ;

    var json_value = try Json.JsonValue.parse(allocator, json_str);
    defer json_value.deinit();

    const person = try json_value.toStruct(Person);
    try std.testing.expect(std.mem.eql(u8, person.name, "John Doe"));
    try std.testing.expect(person.age == null);
    try std.testing.expect(std.mem.eql(u8, person.addr.street, "9641 W Sunset Blvd"));
    try std.testing.expect(std.mem.eql(u8, person.addr.city, "Beverly Hills"));
    try std.testing.expect(person.addr.zip == 90210);

    var json_value_back = try Json.JsonValue.toJsonValue(Person, person, allocator);
    defer json_value_back.deinit();
    const stdout = std.io.getStdOut().writer();
    try json_value_back.print(stdout);
}

test "Parser functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_str =
        \\{
        \\  "name": "John Doe",
        \\  "age": 30,
        \\  "is_student": false,
        \\  "grades": [85.5, 90.0, 78.0],
        \\  "address": {
        \\    "street": "123 Main St",
        \\    "city": "Anytown"
        \\  }
        \\}
    ;
    var json_value = try Json.JsonValue.parse(allocator, json_str);
    defer json_value.deinit();

    const name = try (try json_value.getField("name")).getString();
    try std.testing.expect(std.mem.eql(u8, name, "John Doe"));

    const age = try (try json_value.getField("age")).getNumber();
    try std.testing.expect(age == 30);

    const is_student = try (try json_value.getField("is_student")).getBool();
    try std.testing.expect(is_student == false);

    const grades = try json_value.getField("grades");
    try std.testing.expect(grades.isArray());
    try std.testing.expect(try (try grades.getIndex(0)).getNumber() == 85.5);
    try std.testing.expect(try (try grades.getIndex(1)).getNumber() == 90.0);
    try std.testing.expect(try (try grades.getIndex(2)).getNumber() == 78.0);

    const address = try json_value.getField("address");
    try std.testing.expect(address.isObject());
    const street = try (try address.getField("street")).getString();
    try std.testing.expect(std.mem.eql(u8, street, "123 Main St"));
    const city = try (try address.getField("city")).getString();
    try std.testing.expect(std.mem.eql(u8, city, "Anytown"));
}
