// Simple example program that prints basedirs in YAML

const std = @import("std");
const basedirs = @import("basedirs");
const BaseDirs = basedirs.BaseDirs;

pub fn main() !void {
    var stdout = std.io.getStdOut().writer();

    var allocator = std.heap.page_allocator;

    const dirs = try BaseDirs.init(allocator);

    try stdout.print("basedirs:\n", .{});
    try stdout.print("  home:    {s}\n", .{dirs.home});
    try stdout.print("  data:    {s}\n", .{dirs.data});
    try stdout.print("  config:  {s}\n", .{dirs.config});
    try stdout.print("  cache:   {s}\n", .{dirs.cache});
    try stdout.print("  state:   {s}\n", .{dirs.state});
    try stdout.print("  runtime: {s}\n", .{dirs.runtime});
    try stdout.print("  bin:     {s}\n", .{dirs.bin});
}
