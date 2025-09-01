.PHONY: build cmake debug run pack install clean dump-seed load-seed act release test

cmake:
	mkdir -p build && cd build && cmake -DCMAKE_BUILD_TYPE=Release ..

build: cmake
	cd build && $(MAKE) -j$(shell nproc)

debug:
	mkdir -p build/debug && cd build/debug && cmake -DCMAKE_BUILD_TYPE=Debug ../..
	cd build/debug && $(MAKE) -j$(shell nproc)
	cd build/debug && gdb ./space

run:
	cd build && SPACE_ASSETS_PATH=../assets ./space

pack:
	cd build && cpack

install:
	dpkg -i ./build/space-*-Linux.deb
	apt install -f

clean:
	rm -rf build/*

test:
	ctest --test-dir build --output-on-failure -V

dump-seed:
	python scripts/seed.py dump

load-seed:
	python scripts/seed.py load

# test github workflows
act:
	gh act

# find last version tag, increment, create new tag and push
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
