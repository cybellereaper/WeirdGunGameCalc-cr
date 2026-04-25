.PHONY: build run test clean

build:
	cargo build --release

run:
	cargo run --

test:
	cargo test

clean:
	cargo clean
