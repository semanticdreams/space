.PHONY: build cmake debug run pack install clean dump-seed load-seed

build: cmake
	cd build && $(MAKE) -j$(shell nproc)

cmake:
	@if [ ! -f build/Makefile ] || [ CMakeLists.txt -nt build/Makefile ]; then \
		mkdir -p build && cd build && cmake -DCMAKE_BUILD_TYPE=Release ..; \
	else \
		echo "CMake is up to date."; \
	fi

debug:
	@if [ ! -f build/debug/Makefile ] || [ CMakeLists.txt -nt build/debug/Makefile ]; then \
		mkdir -p build/debug && cd build/debug && cmake -DCMAKE_BUILD_TYPE=Debug ../..; \
	else \
		echo "CMake Debug config is up to date."; \
	fi
	cd build/debug && $(MAKE) -j$(shell nproc)
	cd build/debug && gdb ./space

run: build
	cd build && SPACE_ASSETS_PATH=../assets ./space

pack: build
	cd build && cpack

install: pack
	dpkg -i ./build/space-*-Linux.deb
	apt install -f

clean:
	rm -rf build/*

dump-seed:
	python scripts/seed.py dump

load-seed:
	python scripts/seed.py load
