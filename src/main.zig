const std = @import("std");

const image_size = 1024 * 32;
const max_iterations = 1024;
var pixels: *[image_size * image_size]u8 = undefined;
var current_line: usize = 0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const num_threads = try std.Thread.getCpuCount();

    pixels = try allocator.create([image_size * image_size]u8);
    defer allocator.destroy(pixels);

    var thread_handles = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(thread_handles);

    for (0..num_threads) |i| {
        thread_handles[i] = try std.Thread.spawn(.{}, mandelbrot_worker, .{});
    }

    while (@atomicLoad(usize, &current_line, .Monotonic) < image_size) {
        std.debug.print("\rLine {}/{}", .{ @atomicLoad(usize, &current_line, .Monotonic), image_size });
        std.time.sleep(10 * std.time.ns_per_ms);
    }
    std.debug.print("\n", .{});

    for (0..num_threads) |i| {
        std.debug.print("Waiting for thread {}/{}... ", .{ i + 1, num_threads });
        thread_handles[i].join();
        std.debug.print("Done\n", .{});
    }

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    std.debug.print("Saving image...\n", .{});
    try stdout.print("P5\n{} {}\n255\n", .{ image_size, image_size });

    var pixels_iterator = std.mem.window(u8, pixels, 1024 * 1024 * 1024, 1024 * 1024 * 1024);
    while (pixels_iterator.next()) |bytes| {
        var bytes_to_write = bytes.len;
        while (bytes_to_write > 0) {
            const bytes_written = try stdout.write(bytes[bytes.len - bytes_to_write ..]);
            bytes_to_write -= bytes_written;
        }
    }

    try bw.flush();

    std.debug.print("\nDone.\n", .{});
}

fn mandelbrot_worker() void {
    while (true) {
        const line = @atomicRmw(usize, &current_line, .Add, 1, .Monotonic);
        if (line >= image_size)
            return;
        mandelbrot_line(line);
    }
}

fn mandelbrot_line(y: usize) void {
    for (0..image_size) |x| {
        const c: std.math.Complex(f64) = .{
            .re = (@floatFromInt(f64, x) / @floatFromInt(f64, image_size) - 0.5) * 4.0,
            .im = (@floatFromInt(f64, y) / @floatFromInt(f64, image_size) - 0.5) * 4.0,
        };
        var z = c;
        const value: u8 = for (0..max_iterations) |i| {
            if (z.re * z.re + z.im * z.im > 2 * 2)
                break @intCast(u8, i * 255 / max_iterations);
            z = z.mul(z).add(c);
        } else 0;
        pixels[y * image_size + x] = value;
    }
}
