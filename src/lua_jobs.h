#pragma once

#include <string>
#include <vector>

#include <sol/sol.hpp>

class JobSystem;

void lua_bind_jobs(sol::state& lua, sol::table& lua_space, JobSystem& jobs);

void lua_jobs_dispatch(sol::state& lua, JobSystem& jobs);
void lua_jobs_dispatch_active(sol::state& lua);
void lua_jobs_clear_callbacks();
