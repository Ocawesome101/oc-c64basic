CC=cl65
LD=ld65

all: build

build:
	export CC65_HOME="/usr/share/cc65/"; \
	$(CC) -O --cpu 6502 --config init.cfg -o "../init.bin" -l init.list -r src/*.s
