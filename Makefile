.PHONY: build cmake debug run pack install clean dump-seed load-seed act release

cmake:
	@if [ ! -f build/Makefile ] || [ CMakeLists.txt -nt build/Makefile ]; then \
		mkdir -p build && cd build && cmake -DCMAKE_BUILD_TYPE=Release ..; \
	else \
		echo "CMake is up to date."; \
	fi

build: cmake
	cd build && $(MAKE) -j$(shell nproc)

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

act:
	gh act

release:
	@last_tag=$$(git tag --list 'v*' | sort -V | tail -n1); \
	if [ -z "$$last_tag" ]; then \
		new_version="v1"; \
	else \
		num=$$(echo $$last_tag | sed 's/^v//'); \
		new_num=$$((num + 1)); \
		new_version="v$${new_num}"; \
	fi; \
	echo "Creating new annotated tag $$new_version"; \
	git tag -a $$new_version -m "$$new_version"; \
	git push origin $$new_version
