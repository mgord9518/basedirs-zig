// XDG standard dirs implementation that includes Windows and macOS equivilants
// As it isn't strictly XDG, I've gone with the slightly more general name of
// `base_dirs`

const std = @import("std");
const fmt = std.fmt;
const builtin = @import("builtin");
const os = std.os;

pub fn exePath(buf: []u8) ![]const u8 {
    return switch (builtin.os.tag) {
        .linux => try os.readlink("/proc/self/exe", buf),
        .netbsd => try os.readlink("/proc/curproc/exe", buf),
        .dragonfly => try os.readlink("/proc/self/file", buf),
        .solaris => try os.readlink("/proc/self/a.out", buf),
        .macos, .ios => blk: {
            const DarwinPathError = error{
                NoSpaceLeft,
            };

            const err = os.darwin._NSGetExecutablePath(buf.ptr, buf.len);
            break :blk if (err == 0) std.mem.span(buf.ptr) else DarwinPathError.NoSpaceLeft;
        },
        .windows => blk: {
            // Windows uses WTF-16 encoding, so it has to be converted to UTF-8
            // before returning
            var buf_w: [os.windows.PATH_MAX_WIDE]u16 = undefined;

            const exe_path_w = try os.windows.GetModuleFileNameW(
                null,
                &buf_w,
                buf_w.len,
            );

            var it = std.unicode.Utf16LeIterator.init(exe_path_w);
            var len: usize = 0;

            while (try it.nextCodepoint()) |codepoint| {
                const l = try std.unicode.utf8Encode(codepoint, buf[len..]);
                len += l;
            }

            break :blk buf[0..len];
        },
        else => @compileError("exePath not yet implemented for target OS"),
    };
}

pub const BaseDirs = struct {
    /// Layout based on the XDG base specification.
    /// Some systems may reuse the same direc
    allocator: std.mem.Allocator,
    home: []const u8,
    data: []const u8,
    config: []const u8,
    cache: []const u8,
    state: []const u8,
    runtime: []const u8,
    bin: []const u8,

    /// User vs system integration
    /// NYI
    const Magnitude = enum {
        user,
        system,
    };

    /// Read current values via enviornment variables
    /// System-level paths not yet supported
    pub fn init(allocator: std.mem.Allocator, magnitude: Magnitude) !BaseDirs {
        _ = magnitude;

        const env = try std.process.getEnvMap(allocator);

        // TODO: if $HOME not found, fall back on `/etc/passwd` and non-*nix equivilants
        const home = switch (builtin.os.tag) {
            .windows => env.get("HOMEPATH") orelse "",
            .plan9 => env.get("home") orelse "",
            .haiku => "/boot/home",
            else => env.get("HOME") orelse "",
        };

        const logname = env.get("LOGNAME") orelse "";

        // Assume UID 1000 if unknown
        const uid = if (builtin.os.tag != .windows) blk: {
            const user = std.process.getUserInfo(logname) catch std.process.UserInfo{ .gid = 1000, .uid = 1000 };
            break :blk user.uid;
        };

        return switch (builtin.os.tag) {
            // TODO: properly implement fallbacks
            .windows => .{
                .allocator = allocator,
                .home = home,
                .data = env.get("APPDATA") orelse "",
                .config = env.get("APPDATA") orelse "",
                .cache = env.get("TEMP") orelse "",
                .state = env.get("LOCALAPPDATA") orelse "",
                .runtime = env.get("TEMP") orelse "",
                .bin = env.get("BIN") orelse "\\Windows\\system32",
            },
            .macos => .{
                .allocator = allocator,
                .home = home,
                .data = try fmt.allocPrint(allocator, "{s}/Library", .{home}),
                .config = try fmt.allocPrint(allocator, "{s}/Library/Preferences", .{home}),
                .cache = try fmt.allocPrint(allocator, "{s}/Library/Caches", .{home}),
                .state = try fmt.allocPrint(allocator, "{s}/Library/Preferences", .{home}),
                .runtime = env.get("TMPDIR") orelse try fmt.allocPrint(allocator, "{s}/Library/Caches/TemporaryItems", .{home}),
                .bin = env.get("XDG_BIN_DIR") orelse try fmt.allocPrint(allocator, "{s}/Library/bin", .{home}),
            },
            // Assumes modern *nix XDG standards
            // TODO: create correct fallbacks for other non-*nix OSes like Haiku
            else => .{
                .allocator = allocator,
                .home = home,
                .data = env.get("XDG_DATA_HOME") orelse try fmt.allocPrint(allocator, "{s}/.local/share", .{home}),
                .config = env.get("XDG_CONFIG_HOME") orelse try fmt.allocPrint(allocator, "{s}/.config", .{home}),
                .cache = env.get("XDG_CACHE_HOME") orelse try fmt.allocPrint(allocator, "{s}/.cache", .{home}),
                .state = env.get("XDG_STATE_HOME") orelse try fmt.allocPrint(allocator, "{s}/.local/state", .{home}),
                .runtime = env.get("XDG_RUNTIME_DIR") orelse try fmt.allocPrint(allocator, "/run/user/{d}", .{uid}),
                // This is not XDG standard but I figure the variable might be useful
                .bin = env.get("XDG_BIN_DIR") orelse try fmt.allocPrint(allocator, "{s}/.local/bin", .{home}),
            },
        };
    }

    // TODO: implement
    //pub fn deinit(self: *BaseDirs) void {
    //    self.allocator.free(self.home);
    //}
};
