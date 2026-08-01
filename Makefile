LUA_FILES := control.lua data.lua settings.lua scripts/belts.lua scripts/gui.lua \
             scripts/rates.lua prototypes/styles.lua

.PHONY: help test lint install package icons clean

help: ## Show the available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

test: lint ## Syntax-check Lua, validate locales, then run the tests
	@python3 tests/check_locale.py
	@python3 tests/luarun.py tests/test_rates.lua
	@python3 tests/luarun.py tests/test_machine_line.lua
	@python3 tests/luarun.py tests/test_item_stacking.lua
	@python3 tests/luarun.py tests/test_stepper.lua

lint: ## Syntax-check every Lua file
	@python3 tests/luacheck.py $(LUA_FILES)

icons: ## Regenerate the shortcut icons into graphics/
	@python3 tests/make_icons.py

install: ## Symlink the mod into ~/.factorio/mods
	@ln -sfn $(CURDIR) $(HOME)/.factorio/mods/BeltCapacityHelper
	@echo "linked $(HOME)/.factorio/mods/BeltCapacityHelper -> $(CURDIR)"

package: test ## Build both distributable zips (Factorio 2.0 and 2.1)
	@python3 tests/make_package.py

clean: ## Remove the build directory
	@rm -rf build && echo "build/ removed"
