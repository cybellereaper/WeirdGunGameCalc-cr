.PHONY: build run test update-data clean

build:
	cargo build --release

run:
	cargo run --

test:
	cargo test

update-data:
	cargo run --bin update-data

clean:
	cargo clean
