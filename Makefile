.PHONY: build cmake debug run pack appimage install install-deb install-rpm clean dump-seed load-seed act release test test-e2e test-live-hot-reload test-slow test-integration test-all-lua profile commit prof download-models-data resize-logo docs devlog test-windows-wine

cmake:
	mkdir -p build && cd build && cmake -DCMAKE_BUILD_TYPE=Release -DSPACE_ENABLE_CEF=ON ..

build: cmake
	cd build && $(MAKE) -j$(shell nproc)

debug:
	mkdir -p build/debug && cd build/debug && cmake -DCMAKE_BUILD_TYPE=Debug ../..
	cd build/debug && $(MAKE) -j$(shell nproc)
	cd build/debug && gdb ./space

run:
	cd build && SPACE_FENNEL_PROFILE=1 SPACE_ASSETS_PATH=../assets ./space -m main --remote-control=ipc:///tmp/space-rc.sock

docs:
	cd docs && npm run docs:dev

devlog:
	cd docs && node scripts/open-devlog-entry.mjs

commit:
	codex exec "run `git add -A` and commit with a fitting message"

pack:
	cd build && cpack

appimage: build
	./scripts/build-appimage.sh

install:
	@echo "ambiguous install target; use 'make install-deb' or 'make install-rpm'" >&2
	@exit 1

install-deb:
	@pkg=$$(find ./build -maxdepth 1 -type f \( -name 'space-linux-*.deb' -o -name 'space-*-Linux.deb' \) | head -n 1); \
	if [ -z "$$pkg" ]; then \
		echo "no DEB package artifact found in ./build"; \
		exit 1; \
	fi; \
	if ! command -v dpkg >/dev/null 2>&1; then \
		echo "dpkg not found"; \
		exit 1; \
	fi; \
	dpkg -i "$$pkg" || apt install -f

install-rpm:
	@pkg=$$(find ./build -maxdepth 1 -type f \( -name 'space-linux-*.rpm' -o -name 'space-*-Linux.rpm' \) | head -n 1); \
	if [ -z "$$pkg" ]; then \
		echo "no RPM package artifact found in ./build"; \
		exit 1; \
	fi; \
	if ! command -v dnf >/dev/null 2>&1; then \
		echo "dnf not found"; \
		exit 1; \
	fi; \
	dnf install "$$pkg"

clean:
	rm -rf build/*

test:
	@SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
	SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(shell pwd)/assets \
	FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	xvfb-run -a python3 scripts/ctest-summary.py --test-dir build --output-on-failure -E "^space_fnl_tests_integration$$"

test-e2e:
	SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
	SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(shell pwd)/assets \
	FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	SDL_VIDEODRIVER=x11 xvfb-run -a -s "-screen 0 1280x720x24" ./build/space -m tests.e2e:main

test-slow:
	SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
	SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(shell pwd)/assets \
	FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	./build/space -m tests.slow:main

test-integration:
	SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
	SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(shell pwd)/assets \
	FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	./build/space -m tests.integration:main

test-all-lua:
	SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
	SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(shell pwd)/assets \
	FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	./build/space -m tests.all:main
	SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
	SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(shell pwd)/assets \
	FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	./build/space -m tests.slow:main

test-live-hot-reload:
	SKIP_KEYRING_TESTS=1 XDG_DATA_HOME=/tmp/space/tests/xdg-data SPACE_DISABLE_AUDIO=1 \
	SPACE_LOG_DIR=/tmp/space/tests/log SPACE_ASSETS_PATH=$(shell pwd)/assets \
	FENNEL_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	FENNEL_MACRO_PATH=$(shell pwd)/assets/lua/?.fnl\;$(shell pwd)/assets/lua/?/init.fnl \
	./scripts/test-live-hot-reload.sh

test-windows-wine:
	./scripts/test-windows-under-wine.sh

prof:
	@if [ -z "$(target)" ]; then \
		echo "usage: make prof target=<name>"; \
		exit 1; \
	fi
	python3 scripts/prof.py $(target) $(args)

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

download-models-data:
	wget -O assets/data/models-dot-dev.json https://models.dev/api.json

resize-logo:
	mv assets/pics/space.png assets/pics/space.old.png
	ffmpeg -i assets/pics/space.old.png -vf "scale=256:-1:flags=lanczos" assets/pics/space.png
