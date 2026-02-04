#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "lua_jobs.h"

#include "gltf_mesh_job.h"
#include "job_system.h"
#include "lua_callbacks.h"
#include "lua_cgltf.h"

namespace {

struct SubmitArgs {
    std::string kind;
    std::string payload;
    sol::optional<sol::function> callback;
};

SubmitArgs parse_submit(sol::variadic_args args) {
    if (args.size() == 0) {
        throw sol::error("jobs.submit requires a kind");
    }

    std::size_t idx = 0;
    sol::object first = args[idx];
    sol::optional<sol::table> opts;
    if (first.is<sol::table>()) {
        opts = first.as<sol::table>();
        idx += 1;
    }

    sol::object kindObj = (opts ? opts->get<sol::object>("kind") : args[idx]);
    if (!kindObj.is<std::string>()) {
        throw sol::error("jobs.submit kind must be a string");
    }
    std::string kind = kindObj.as<std::string>();

    std::string payload;
    if (opts) {
        sol::object payloadObj = opts->get<sol::object>("payload");
        if (payloadObj.is<std::string>()) {
            payload = payloadObj.as<std::string>();
        }
    } else if (args.size() > idx + 1) {
        sol::object payloadObj = args[idx + 1];
        if (payloadObj.is<std::string>()) {
            payload = payloadObj.as<std::string>();
        }
    }

    sol::optional<sol::function> cb;
    if (opts) {
        sol::object cb_obj = opts->get<sol::object>("callback");
        if (cb_obj.is<sol::function>()) {
            cb = cb_obj.as<sol::function>();
        }
    } else if (args.size() > idx + 2) {
        sol::object cb_obj = args[idx + 2];
        if (cb_obj.is<sol::function>()) {
            cb = cb_obj.as<sol::function>();
        }
    }

    return SubmitArgs { std::move(kind), std::move(payload), cb };
}

std::optional<std::size_t> parse_max_results(sol::variadic_args args) {
    if (args.size() == 0) {
        return std::nullopt;
    }

    std::size_t idx = 0;
    if (args[0].is<sol::table>()) {
        idx += 1;
    }
    if (args.size() <= idx) {
        return std::nullopt;
    }

    sol::object value = args[idx];
    if (value.is<uint64_t>()) {
        return value.as<uint64_t>();
    }
    if (value.is<int>()) {
        int asInt = value.as<int>();
        if (asInt < 0) {
            throw sol::error("jobs.poll max_results must be non-negative");
        }
        return static_cast<std::size_t>(asInt);
    }
    if (value.is<double>()) {
        double asDouble = value.as<double>();
        if (asDouble < 0.0) {
            throw sol::error("jobs.poll max_results must be non-negative");
        }
        return static_cast<std::size_t>(asDouble);
    }
    return std::nullopt;
}

std::unordered_map<uint64_t, uint64_t> job_callbacks;
std::vector<JobSystem::JobResult> buffered_results;
JobSystem* active_jobs = nullptr;
void clear_ready_callbacks() {
    job_callbacks.clear();
    buffered_results.clear();
}

void attach_payload(sol::state_view lua, sol::table& item, JobSystem::JobResult& res)
{
    if (res.kind == "load_gltf") {
        if (res.ok && res.payload.data) {
            auto* data = static_cast<cgltf_data*>(res.payload.data);
            item["data"] = cgltf_adopt_data(data);
            res.payload.owner.release();
        } else {
            item["data"] = sol::lua_nil;
        }
        return;
    }

    if (res.kind == "build_gltf_batches") {
        if (res.ok && res.payload.data) {
            auto* payload = static_cast<GltfMeshJobResult*>(res.payload.data);
            sol::table batches = lua.create_table(static_cast<int>(payload->batches.size()), 0);
            int batch_index = 1;
            for (auto& batch : payload->batches) {
                sol::table entry = lua.create_table();
                if (!batch.vertices.empty()) {
                    const char* data = reinterpret_cast<const char*>(batch.vertices.data());
                    std::size_t byte_count = batch.vertices.size() * sizeof(float);
                    entry["vertex_bytes"] = std::string(data, byte_count);
                } else {
                    entry["vertex_bytes"] = sol::lua_nil;
                }
                entry["vertex_count"] = static_cast<int>(batch.vertices.size() / 8);
                if (batch.image_index > 0) {
                    entry["image-index"] = batch.image_index;
                } else {
                    entry["image-index"] = sol::lua_nil;
                }
                if (!batch.image_uri.empty()) {
                    entry["image-uri"] = batch.image_uri;
                } else {
                    entry["image-uri"] = sol::lua_nil;
                }
                if (!batch.image_bytes.empty()) {
                    entry["image-bytes"] = batch.image_bytes;
                } else {
                    entry["image-bytes"] = sol::lua_nil;
                }
                batches[batch_index++] = entry;
            }
            item["batches"] = batches;
            sol::table bounds = lua.create_table();
            if (payload->has_bounds) {
                sol::table min = lua.create_table();
                min["x"] = payload->bounds_min[0];
                min["y"] = payload->bounds_min[1];
                min["z"] = payload->bounds_min[2];
                sol::table max = lua.create_table();
                max["x"] = payload->bounds_max[0];
                max["y"] = payload->bounds_max[1];
                max["z"] = payload->bounds_max[2];
                bounds["min"] = min;
                bounds["max"] = max;
            } else {
                bounds["min"] = sol::lua_nil;
                bounds["max"] = sol::lua_nil;
            }
            item["bounds"] = bounds;
        } else {
            item["batches"] = sol::lua_nil;
            item["bounds"] = sol::lua_nil;
        }
        return;
    }

    if (res.kind == "decode_texture_bytes") {
        if (res.ok && res.payload.data) {
            const char* data = reinterpret_cast<const char*>(res.payload.data);
            item["pixel-bytes"] = std::string(data, res.payload.size_bytes);
            item["width"] = res.aux_a;
            item["height"] = res.aux_b;
            item["channels"] = res.aux_c;
        } else {
            item["pixel-bytes"] = sol::lua_nil;
            item["width"] = sol::lua_nil;
            item["height"] = sol::lua_nil;
            item["channels"] = sol::lua_nil;
        }
        return;
    }

    if (res.payload.size_bytes > 0 && res.payload.alignment >= alignof(std::uint8_t)) {
        auto* bytes = static_cast<std::uint8_t*>(res.payload.data);
        if (bytes) {
            sol::table arr = lua.create_table(static_cast<int>(res.payload.size_bytes), 0);
            for (std::size_t i = 0; i < res.payload.size_bytes; ++i) {
                arr[static_cast<int>(i + 1)] = bytes[i];
            }
            item["binary"] = arr;
        }
    }

    if (res.aux_a != 0 || res.aux_b != 0 || res.aux_c != 0 || res.aux_d != 0) {
        item["aux-a"] = res.aux_a;
        item["aux-b"] = res.aux_b;
        item["aux-c"] = res.aux_c;
        item["aux-d"] = res.aux_d;
    }
}

void enqueue_job_callback(JobSystem::JobResult&& res) {
    auto it = job_callbacks.find(res.id);
    if (it == job_callbacks.end()) {
        buffered_results.push_back(std::move(res));
        return;
    }
    uint64_t cb_id = it->second;
    job_callbacks.erase(it);
    auto payload = std::make_shared<JobSystem::JobResult>(std::move(res));
    lua_callbacks_enqueue(cb_id, [payload](sol::state_view lua) {
        sol::table item = lua.create_table();
        item["id"] = payload->id;
        item["ok"] = payload->ok;
        item["kind"] = payload->kind;
        if (payload->ok) {
            item["result"] = payload->result;
            item["error"] = sol::lua_nil;
        } else {
            item["result"] = sol::lua_nil;
            item["error"] = payload->error;
        }
        attach_payload(lua, item, *payload);
        return sol::make_object(lua, item);
    });
}

} // namespace

void lua_jobs_clear_callbacks() {
    clear_ready_callbacks();
    active_jobs = nullptr;
}

void lua_jobs_dispatch(sol::state& lua, JobSystem& jobs) {
    std::vector<JobSystem::JobResult> results = jobs.poll_owner(JobSystem::JobOwner::Lua, 0);
    for (auto& res : results) {
        enqueue_job_callback(std::move(res));
    }
    // flush any buffered results without callbacks back into the Lua poll queue
    if (!buffered_results.empty()) {
        // keep them buffered; poll will consume
    }
    lua_callbacks_dispatch(lua);
}

void lua_jobs_dispatch_active(sol::state& lua)
{
    if (!active_jobs) {
        return;
    }
    lua_jobs_dispatch(lua, *active_jobs);
}

void lua_bind_jobs(sol::state& lua, sol::table& lua_space, JobSystem& jobs) {
    active_jobs = &jobs;
    sol::table jobTable = lua.create_table();

    jobTable.set_function("submit",
                          [&lua, &jobs](sol::variadic_args args) {
                              SubmitArgs parsed = parse_submit(args);
                              uint64_t id = jobs.submit(parsed.kind, parsed.payload, JobSystem::JobOwner::Lua);
                              if (parsed.callback) {
                                  uint64_t cb_id = lua_callbacks_register(parsed.callback.value());
                                  job_callbacks[id] = cb_id;
                              }
                              return id;
                          });

    jobTable.set_function("poll",
                          [&lua, &jobs](sol::variadic_args args) {
                              auto maxResults = parse_max_results(args);
                              std::vector<JobSystem::JobResult> results;
                              if (!buffered_results.empty()) {
                                  if (maxResults && maxResults.value() > 0 && maxResults.value() < buffered_results.size()) {
                                      results.insert(results.end(),
                                                     std::make_move_iterator(buffered_results.begin()),
                                                     std::make_move_iterator(buffered_results.begin() + static_cast<std::ptrdiff_t>(maxResults.value())));
                                      buffered_results.erase(buffered_results.begin(),
                                                             buffered_results.begin() + static_cast<std::ptrdiff_t>(maxResults.value()));
                                  } else {
                                      results.swap(buffered_results);
                                  }
                              }
                              std::vector<JobSystem::JobResult> polled =
                                  jobs.poll_owner(JobSystem::JobOwner::Lua, maxResults.value_or(0));
                              results.insert(results.end(),
                                             std::make_move_iterator(polled.begin()),
                                             std::make_move_iterator(polled.end()));
                              sol::table output = lua.create_table();
                              std::size_t idx = 1;
                              for (auto& res : results) {
                                  auto it = job_callbacks.find(res.id);
                                  if (it != job_callbacks.end()) {
                                      uint64_t cb_id = it->second;
                                      auto payload = std::make_shared<JobSystem::JobResult>(std::move(res));
                                      lua_callbacks_enqueue(cb_id, [payload](sol::state_view l) {
                                          sol::table item = l.create_table();
                                          item["id"] = payload->id;
                                          item["ok"] = payload->ok;
                                          item["kind"] = payload->kind;
                                          if (payload->ok) {
                                              item["result"] = payload->result;
                                              item["error"] = sol::lua_nil;
                                          } else {
                                              item["result"] = sol::lua_nil;
                                              item["error"] = payload->error;
                                          }
                                          return sol::make_object(l, item);
                                      });
                                      job_callbacks.erase(it);
                                  } else {
                                      sol::table item = lua.create_table();
                                      item["id"] = res.id;
                                      item["ok"] = res.ok;
                                      item["kind"] = res.kind;
                                      if (res.ok) {
                                          item["result"] = res.result;
                                          item["error"] = sol::lua_nil;
                                      } else {
                                          item["result"] = sol::lua_nil;
                                          item["error"] = res.error;
                                      }
                                      attach_payload(lua, item, res);
                                      output[idx++] = item;
                                  }
                              }
                              lua_callbacks_dispatch(lua);
                              return output;
                          });

    lua_space["jobs"] = jobTable;

    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("jobs", [jobTable](sol::this_state state) mutable {
        (void)state;
        return jobTable;
    });
}
