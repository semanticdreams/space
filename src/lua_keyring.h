#pragma once

#include <sol/sol.hpp>

#include "keyring.h"

void lua_bind_keyring(sol::state& lua, Keyring& keyring);
void lua_keyring_drop(sol::state& lua);
