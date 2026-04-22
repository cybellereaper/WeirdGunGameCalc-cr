.PHONY: build run test update-data clean

build:
	shards build --release

run:
	crystal run src/main.cr --

test:
	crystal spec

update-data:
	crystal run ParseSheet.cr

clean:
	rm -rf .shards shard.lock bin .crystal
