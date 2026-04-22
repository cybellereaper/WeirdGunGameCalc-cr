.PHONY: build run test clean

build:
	shards build --release

run:
	crystal run src/main.cr --

test:
	crystal spec

clean:
	rm -rf .shards shard.lock bin .crystal
