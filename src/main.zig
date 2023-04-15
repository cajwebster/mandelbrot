const std = @import("std");

const image_size = 1024 * 32;
const max_iterations = 1024;
var pixels: [image_size * image_size]u8 = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    const num_threads = try std.Thread.getCpuCount();
    const thread_image_height = image_size / num_threads;

    var thread_handles = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(thread_handles);

    for (0..num_threads) |i| {
        const ymin = thread_image_height * i;
        const ymax = ymin + thread_image_height;
        thread_handles[i] = try std.Thread.spawn(.{}, mandelbrot, .{ ymin, ymax });
    }

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
    _ = try stdout.write(&pixels);

    std.debug.print("\nDone.\n", .{});

    try bw.flush();
}

fn mandelbrot(ymin: usize, ymax: usize) void {
    for (ymin..ymax) |y| {
        for (0..image_size) |x| {
            const c: std.math.Complex(f64) = .{
                .re = (@intToFloat(f64, x) / @intToFloat(f64, image_size) - 0.5) * 4.0,
                .im = (@intToFloat(f64, y) / @intToFloat(f64, image_size) - 0.5) * 4.0,
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
}
