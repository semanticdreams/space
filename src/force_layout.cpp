#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <omp.h>
#include <stdexcept>
#include <iostream>
#include <sstream>
#include <utility>

#include "force_layout.h"
#include "force_layout_quad_tree.hpp"

namespace {

constexpr double kPositionMagnitudeThreshold = 1e6;

void assert_valid_position(const glm::vec3& pos, const char* context, size_t index) {
    if (!std::isfinite(pos.x) || !std::isfinite(pos.y) || !std::isfinite(pos.z)) {
        std::ostringstream message;
        message << "ForceLayout received non-finite position in " << context << " for index " << index;
        throw std::runtime_error(message.str());
    }
    double magnitude = glm::length(pos);
    if (!std::isfinite(magnitude) || magnitude > kPositionMagnitudeThreshold) {
        std::ostringstream message;
        message << "ForceLayout position magnitude " << magnitude << " exceeds threshold "
                << kPositionMagnitudeThreshold << " in " << context << " for index " << index;
        throw std::runtime_error(message.str());
    }
}

const glm::vec3& default_bounds_min() {
    static const glm::vec3 min_bounds(-std::numeric_limits<float>::infinity(), -100.0f,
                                      -std::numeric_limits<float>::infinity());
    return min_bounds;
}

const glm::vec3& default_bounds_max() {
    static const glm::vec3 max_bounds(std::numeric_limits<float>::infinity(), 500.0f,
                                      std::numeric_limits<float>::infinity());
    return max_bounds;
}

} // namespace

int ForceLayoutSignal::connect(const sol::function& callback) {
    sol::protected_function fn = callback;
    int id = nextId++;
    callbacks.emplace_back(id, std::move(fn));
    return id;
}

void ForceLayoutSignal::disconnect(int id, bool allowMissing) {
    auto it = std::remove_if(callbacks.begin(), callbacks.end(),
                             [id](const auto& entry) { return entry.first == id; });
    bool removed = it != callbacks.end();
    callbacks.erase(it, callbacks.end());
    if (!removed && !allowMissing) {
        throw std::runtime_error("ForceLayoutSignal handler not connected");
    }
}

void ForceLayoutSignal::clear() {
    callbacks.clear();
}

size_t ForceLayoutSignal::size() const {
    return callbacks.size();
}

void ForceLayoutSignal::emit() {
    auto snapshot = callbacks;
    for (auto& entry : snapshot) {
        auto& fn = entry.second;
        if (!fn.valid()) {
            continue;
        }
        sol::protected_function_result result = fn();
        if (!result.valid()) {
            sol::error err = result;
            // Avoid throwing into Lua update loops; surface error to stderr.
            std::cerr << "[ForceLayoutSignal] callback error: " << err.what() << std::endl;
        }
    }
}

ForceLayout::ForceLayout()
    : ForceLayout(glm::vec3(0.0f),
                  50.0,
                  6250.0,
                  1.0,
                  0.02,
                  0.0001,
                  0.02,
                  0.01,
                  100.0,
                  0.1,
                  default_bounds_min(),
                  default_bounds_max(),
                  true) {}

ForceLayout::ForceLayout(const glm::vec3& center_position_,
                         double spring_rest_length_,
                         double repulsive_force_constant_,
                         double spring_constant_,
                         double delta_t_,
                         double center_force_,
                         double stabilized_max_displacement_,
                         double stabilized_avg_displacement_,
                         double max_displacement_squared_,
                         double update_interval_)
    : ForceLayout(center_position_,
                  spring_rest_length_,
                  repulsive_force_constant_,
                  spring_constant_,
                  delta_t_,
                  center_force_,
                  stabilized_max_displacement_,
                  stabilized_avg_displacement_,
                  max_displacement_squared_,
                  update_interval_,
                  default_bounds_min(),
                  default_bounds_max(),
                  true) {}

ForceLayout::ForceLayout(const glm::vec3& center_position_,
                         double spring_rest_length_,
                         double repulsive_force_constant_,
                         double spring_constant_,
                         double delta_t_,
                         double center_force_,
                         double stabilized_max_displacement_,
                         double stabilized_avg_displacement_,
                         double max_displacement_squared_,
                         double update_interval_,
                         const glm::vec3& bounds_min_,
                         const glm::vec3& bounds_max_,
                         bool auto_center_within_bounds_)
    : spring_rest_length(spring_rest_length_),
      repulsive_force_constant(repulsive_force_constant_),
      spring_constant(spring_constant_),
      delta_t(delta_t_),
      center_force(center_force_),
      stabilized_max_displacement(stabilized_max_displacement_),
      stabilized_avg_displacement(stabilized_avg_displacement_),
      max_displacement_squared(max_displacement_squared_),
      update_interval(update_interval_),
      center_position(center_position_.x, center_position_.y),
      bounds_min(bounds_min_),
      bounds_max(bounds_max_),
      auto_center_within_bounds(auto_center_within_bounds_) {
    refresh_center_from_bounds();
    clear();
}

void ForceLayout::clear() {
    positions.clear();
    edges.clear();
    pinned.clear();
    forces.clear();
    last_results = std::make_tuple(0.0, 0.0, 0.0);
    active = false;
    callback = sol::nil;
}

int ForceLayout::add_node(const glm::vec3& pos) {
    size_t idx = positions.size();
    assert_valid_position(pos, "add_node", idx);
    positions.push_back(clamp_to_bounds(pos));
    edges.emplace_back();
    pinned.push_back(false);
    forces.emplace_back(0.0);
    return static_cast<int>(idx);
}

void ForceLayout::add_edge(int source, int target, bool mirror) {
    if (source < 0 || target < 0) return;
    if (static_cast<size_t>(source) >= edges.size() || static_cast<size_t>(target) >= edges.size()) return;
    edges[static_cast<size_t>(source)].push_back(target);
    if (mirror) edges[static_cast<size_t>(target)].push_back(source);
}

void ForceLayout::set_position(int idx, const glm::vec3& pos) {
    if (idx < 0 || static_cast<size_t>(idx) >= positions.size()) return;
    assert_valid_position(pos, "set_position", static_cast<size_t>(idx));
    positions[static_cast<size_t>(idx)] = clamp_to_bounds(pos);
}

void ForceLayout::pin_node(int idx, bool value) {
    if (idx < 0 || static_cast<size_t>(idx) >= pinned.size()) return;
    pinned[static_cast<size_t>(idx)] = value;
}

std::tuple<double, double, double> ForceLayout::step(int num_iterations) {
    size_t n = positions.size();
    if (n == 0) {
        last_results = std::make_tuple(0.0, 0.0, 0.0);
        return last_results;
    }

    std::vector<glm::dvec2> xy_positions(n);
    for (size_t i = 0; i < n; ++i) {
        assert_valid_position(positions[i], "step:pre", i);
        positions[i] = clamp_to_bounds(positions[i]);
        xy_positions[i] = glm::dvec2(positions[i].x, positions[i].y);
    }

    for (int iter = 0; iter < num_iterations; ++iter) {
        forces.assign(n, glm::dvec2(0.0));

        // Compute bounds for quadtree
        glm::dvec2 minPos = xy_positions[0];
        glm::dvec2 maxPos = xy_positions[0];
        for (size_t i = 1; i < n; ++i) {
            minPos = glm::min(minPos, xy_positions[i]);
            maxPos = glm::max(maxPos, xy_positions[i]);
        }
        glm::dvec2 center = (minPos + maxPos) * 0.5;
        glm::dvec2 extent = maxPos - minPos;
        double maxDim = std::max(extent.x, extent.y) * 0.5 + 1.0;

        // Build quadtree
        QuadTreeNode tree(center, maxDim <= 0.0 ? 1.0 : maxDim);
        for (size_t i = 0; i < n; ++i) {
            tree.insert(static_cast<int>(i), xy_positions[i], xy_positions);
        }
        tree.finalizeMass();

        // Repulsive forces (Barnes-Hut)
        std::vector<std::vector<glm::dvec2>> local_forces;
        int num_threads = omp_get_max_threads();
        local_forces.resize(static_cast<size_t>(num_threads), std::vector<glm::dvec2>(n, glm::dvec2(0.0)));

#pragma omp parallel
        {
            int tid = omp_get_thread_num();
            auto& local = local_forces[static_cast<size_t>(tid)];

#pragma omp for
            for (int i = 0; i < static_cast<int>(n); ++i) {
                tree.computeRepulsion(i, xy_positions[static_cast<size_t>(i)], local[static_cast<size_t>(i)],
                                      xy_positions, 0.5, repulsive_force_constant);
            }
        }

        std::fill(forces.begin(), forces.end(), glm::dvec2(0.0));
        for (int t = 0; t < num_threads; ++t) {
            auto& local = local_forces[static_cast<size_t>(t)];
            for (size_t i = 0; i < n; ++i) {
                forces[i] += local[i];
            }
        }

        // Attractive (spring) forces
        for (size_t i = 0; i < n; ++i) {
            glm::dvec2 pi = xy_positions[i];
            for (int j : edges[i]) {
                if (static_cast<size_t>(j) <= i) {
                    continue;
                }
                glm::dvec2 pj = xy_positions[static_cast<size_t>(j)];
                glm::dvec2 delta = pi - pj;
                double dist = glm::length(delta);
                if (dist == 0.0) continue;

                double force_mag = spring_constant * (dist - spring_rest_length);
                glm::dvec2 f = force_mag * (delta / dist);

                forces[i] -= f;
                forces[static_cast<size_t>(j)] += f;
            }
        }

        // Centering force
        for (size_t i = 0; i < n; ++i) {
            glm::dvec2 diff = center_position - xy_positions[i];
            glm::dvec2 center_force_vec = center_force * diff * glm::abs(diff);
            forces[i] += center_force_vec;
        }

        // Integrate forces and update positions
        double total = 0.0;
        double max_d = 0.0;
        for (size_t i = 0; i < n; ++i) {
            if (pinned[i]) {
                positions[i] = clamp_to_bounds(positions[i]);
                xy_positions[i] = glm::dvec2(positions[i].x, positions[i].y);
                continue;
            }

            glm::dvec2 disp = delta_t * forces[i];
            double disp_sq = glm::dot(disp, disp);
            double scale = 1.0;
            if (disp_sq > max_displacement_squared) {
                scale = std::sqrt(max_displacement_squared / disp_sq);
            }

            glm::dvec2 delta = disp * scale;
            positions[i].x += delta.x;
            positions[i].y += delta.y;
            positions[i] = clamp_to_bounds(positions[i]);
            assert_valid_position(positions[i], "step:post", i);
            xy_positions[i] = glm::dvec2(positions[i].x, positions[i].y);

            double dist = glm::length(delta);
            total += dist;
            if (dist > max_d) {
                max_d = dist;
            }
        }

        last_results = std::make_tuple(total, total / static_cast<double>(n), max_d);
    }

    return last_results;
}

std::tuple<double, double, double> ForceLayout::update(int num_iterations) {
    if (!active) {
        return last_results;
    }
    last_results = step(num_iterations);
    double average = std::get<1>(last_results);
    double max_d = std::get<2>(last_results);
    if (average < stabilized_avg_displacement && max_d < stabilized_max_displacement) {
        stop();
        emit_stabilized();
    }
    return last_results;
}

void ForceLayout::start(sol::optional<sol::function> callback_) {
    if (callback_) {
        callback = callback_.value();
    } else {
        callback = sol::nil;
    }
    active = true;
    emit_changed();
}

void ForceLayout::cancel() {
    active = false;
    emit_changed();
}

void ForceLayout::stop() {
    active = false;
    if (callback.valid()) {
        sol::protected_function fn = callback;
        sol::protected_function_result result = fn();
        if (!result.valid()) {
            sol::error err = result;
            std::cerr << "[ForceLayout] callback error: " << err.what() << std::endl;
        }
        callback = sol::nil;
    }
    emit_changed();
}

void ForceLayout::run(sol::optional<sol::function> callback_) {
    if (active) {
        active = false;
    }
    start(callback_);
}

void ForceLayout::until_stable(int iterations_per_update, double timeout_seconds) {
    auto start_time = std::chrono::steady_clock::now();
    start();
    while (active) {
        update(iterations_per_update);
        auto elapsed = std::chrono::steady_clock::now() - start_time;
        double seconds = std::chrono::duration<double>(elapsed).count();
        if (seconds > timeout_seconds) {
            stop();
            break;
        }
    }
}

size_t ForceLayout::positions_size() const {
    return positions.size();
}

glm::vec3& ForceLayout::position_at(size_t index) {
    return positions.at(index);
}

const glm::vec3& ForceLayout::position_at(size_t index) const {
    return positions.at(index);
}

void ForceLayout::set_center_position(const glm::vec3& pos) {
    center_position = glm::dvec2(pos.x, pos.y);
}

glm::vec3 ForceLayout::get_center_position() const {
    return glm::vec3(center_position, 0.0);
}

void ForceLayout::set_bounds(const glm::vec3& min, const glm::vec3& max) {
    glm::dvec3 min_d(min);
    glm::dvec3 max_d(max);
    bounds_min = glm::min(min_d, max_d);
    bounds_max = glm::max(min_d, max_d);
    for (auto& pos : positions) {
        pos = clamp_to_bounds(pos);
    }
    refresh_center_from_bounds();
}

void ForceLayout::set_bounds(const std::pair<glm::vec3, glm::vec3>& bounds) {
    set_bounds(bounds.first, bounds.second);
}

std::pair<glm::vec3, glm::vec3> ForceLayout::get_bounds() const {
    return {glm::vec3(bounds_min), glm::vec3(bounds_max)};
}

void ForceLayout::set_auto_center_within_bounds(bool enabled) {
    auto_center_within_bounds = enabled;
    refresh_center_from_bounds();
}

bool ForceLayout::get_auto_center_within_bounds() const {
    return auto_center_within_bounds;
}

std::tuple<double, double, double> ForceLayout::get_results() const {
    return last_results;
}

ForceLayoutSignal& ForceLayout::changed_signal() {
    return changed;
}

ForceLayoutSignal& ForceLayout::stabilized_signal() {
    return stabilized;
}

bool ForceLayout::is_active() const {
    return active;
}

size_t ForceLayout::node_count() const {
    return positions.size();
}

void ForceLayout::emit_changed() {
    changed.emit();
}

void ForceLayout::emit_stabilized() {
    stabilized.emit();
}

void ForceLayout::refresh_center_from_bounds() {
    if (!auto_center_within_bounds) {
        return;
    }

    glm::dvec2 new_center = center_position;
    if (std::isfinite(bounds_min.x) && std::isfinite(bounds_max.x)) {
        new_center.x = (bounds_min.x + bounds_max.x) * 0.5;
    }
    if (std::isfinite(bounds_min.y) && std::isfinite(bounds_max.y)) {
        new_center.y = (bounds_min.y + bounds_max.y) * 0.5;
    }
    center_position = new_center;
}

glm::vec3 ForceLayout::clamp_to_bounds(const glm::vec3& pos) const {
    glm::vec3 clamped = pos;
    if (std::isfinite(bounds_min.x)) {
        clamped.x = std::max(clamped.x, static_cast<float>(bounds_min.x));
    }
    if (std::isfinite(bounds_max.x)) {
        clamped.x = std::min(clamped.x, static_cast<float>(bounds_max.x));
    }
    if (std::isfinite(bounds_min.y)) {
        clamped.y = std::max(clamped.y, static_cast<float>(bounds_min.y));
    }
    if (std::isfinite(bounds_max.y)) {
        clamped.y = std::min(clamped.y, static_cast<float>(bounds_max.y));
    }
    if (std::isfinite(bounds_min.z)) {
        clamped.z = std::max(clamped.z, static_cast<float>(bounds_min.z));
    }
    if (std::isfinite(bounds_max.z)) {
        clamped.z = std::min(clamped.z, static_cast<float>(bounds_max.z));
    }
    return clamped;
}
