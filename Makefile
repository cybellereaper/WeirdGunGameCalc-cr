.PHONY: build run test clean

build:
	zig build -Doptimize=ReleaseFast

run:
	zig build run --

test:
	zig build test

clean:
	rm -rf .zig-cache zig-out
