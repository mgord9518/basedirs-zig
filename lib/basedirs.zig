// XDG standard dirs implementation that includes Windows and macOS equivilants
// As it isn't strictly XDG, I've gone with the slightly more general name of
// `base_dirs`

const std = @import("std");
const fmt = std.fmt;
const builtin = @import("builtin");
const os = std.os;

/// Layout based on the XDG base specification.
/// Some systems may reuse the same directories for different basedirs as there
/// is no 1:1 reflection on all common systems
pub const BaseDirs = struct {
    allocator: std.mem.Allocator,
    home: []const u8,
    data: []const u8,
    config: []const u8,
    cache: []const u8,
    state: []const u8,
    runtime: []const u8,
    bin: []const u8,

    /// Read current values via enviornment variables
    pub fn init(allocator: std.mem.Allocator) !BaseDirs {
        var env = try std.process.getEnvMap(allocator);
        //defer env.deinit();

        const logname = env.get("LOGNAME") orelse "";

        // Assume UID 1000 if unknown
        const uid = if (builtin.os.tag != .windows) blk: {
            const user = std.process.getUserInfo(logname) catch std.process.UserInfo{ .gid = 1000, .uid = 1000 };
            break :blk user.uid;
        };

        // TODO: if $HOME not found, fall back on `/etc/passwd` and non-*nix equivilants
        const home = switch (builtin.os.tag) {
            .windows => env.get("USERPROFILE") orelse "",
            .plan9 => env.get("home") orelse try homeFromPasswd(0),
            .haiku => "/boot/home",
            else => env.get("HOME") orelse try homeFromPasswd(uid),
        };

        return switch (builtin.os.tag) {
            // TODO: properly implement fallbacks
            .windows => blk: {
                const homedrive = env.get("HOMEDRIVE") orelse "C:";
                break :blk .{
                    .allocator = allocator,
                    .home = home,
                    .data = env.get("APPDATA") orelse "",
                    .config = env.get("APPDATA") orelse "",
                    .cache = env.get("TEMP") orelse "",
                    .state = env.get("LOCALAPPDATA") orelse "",
                    .runtime = env.get("TEMP") orelse "",
                    .bin = env.get("BIN") orelse try fmt.allocPrint(allocator, "{s}\\Windows\\system32", .{homedrive}),
                };
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

// Parses homedir from `/etc/passwd` on POSIX systems
fn homeFromPasswd(uid: std.os.uid_t) ![]const u8 {
    // This should be more than enough for even incredibly long entries
    // On my system the longest was <100 chars, but this should eventually have
    // a heap-allocated fallback if for some reason a line exceeds this buffer
    var buf: [512]u8 = undefined;

    var cwd = std.fs.cwd();

    var passwd = try cwd.openFile("/etc/passwd", .{});
    var stream = std.io.bufferedReader(passwd.reader());
    var buf_stream = stream.reader();

    while (try buf_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        var it = std.mem.splitScalar(u8, line, ':');

        var uid_found = false;
        var idx: usize = 0;
        while (it.next()) |token| {
            // UID field of passwd
            if (idx == 2) {
                const parsed_uid = try std.fmt.parseInt(std.os.uid_t, token, 10);

                uid_found = (parsed_uid == uid);
            }

            //std.debug.print("{} ", .{uid_found});

            // If the current line doesn't have our wanted UID, there's no
            // reason to continue parsing it, so skip to the next line
            //
            // TODO: fix this. For some reason it doesn't recognize the block
            // when placed in the parent loop
            if (idx >= 2 and !uid_found) {
                idx += 1;
                //continue :blk;
                continue;
            }

            // Home directory field of passwd
            if (uid_found and idx == 5) {
                return token;
            }

            idx += 1;
        }
    }

    unreachable;
}
