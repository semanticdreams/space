#pragma once

#include <sol/sol.hpp>
#include <glm/glm.hpp>
#include <tuple>
#include <utility>
#include <vector>

class ForceLayoutSignal {
public:
    int connect(const sol::function& callback);
    void disconnect(int id, bool allowMissing = false);
    void clear();
    size_t size() const;
    void emit();

private:
    int nextId = 1;
    std::vector<std::pair<int, sol::protected_function>> callbacks;
};

class ForceLayout {
public:
    ForceLayout();
    ForceLayout(const glm::vec3& center_position,
                double spring_rest_length,
                double repulsive_force_constant,
                double spring_constant,
                double delta_t,
                double center_force,
                double stabilized_max_displacement,
                double stabilized_avg_displacement,
                double max_displacement_squared,
                double update_interval);
    ForceLayout(const glm::vec3& center_position,
                double spring_rest_length,
                double repulsive_force_constant,
                double spring_constant,
                double delta_t,
                double center_force,
                double stabilized_max_displacement,
                double stabilized_avg_displacement,
                double max_displacement_squared,
                double update_interval,
                const glm::vec3& bounds_min,
                const glm::vec3& bounds_max,
                bool auto_center_within_bounds = true);

    void clear();
    int add_node(const glm::vec3& pos);
    void add_edge(int source, int target, bool mirror = true);
    void set_position(int idx, const glm::vec3& pos);
    void pin_node(int idx, bool value = true);
    std::tuple<double, double, double> step(int num_iterations = 10);
    std::tuple<double, double, double> update(int num_iterations = 1000);
    void start(sol::optional<sol::function> callback = sol::nullopt);
    void cancel();
    void stop();
    void run(sol::optional<sol::function> callback = sol::nullopt);
    void until_stable(int iterations_per_update = 1, double timeout_seconds = 10.0);
    size_t positions_size() const;
    glm::vec3& position_at(size_t index);
    const glm::vec3& position_at(size_t index) const;
    void set_center_position(const glm::vec3& pos);
    glm::vec3 get_center_position() const;
    void set_bounds(const glm::vec3& min, const glm::vec3& max);
    void set_bounds(const std::pair<glm::vec3, glm::vec3>& bounds);
    std::pair<glm::vec3, glm::vec3> get_bounds() const;
    void set_auto_center_within_bounds(bool enabled);
    bool get_auto_center_within_bounds() const;
    std::tuple<double, double, double> get_results() const;
    ForceLayoutSignal& changed_signal();
    ForceLayoutSignal& stabilized_signal();
    bool is_active() const;
    size_t node_count() const;

    double spring_rest_length;
    double repulsive_force_constant;
    double spring_constant;
    double delta_t;
    double center_force;
    double stabilized_max_displacement;
    double stabilized_avg_displacement;
    double max_displacement_squared;
    double update_interval;

private:
    glm::dvec2 center_position;
    glm::dvec3 bounds_min;
    glm::dvec3 bounds_max;
    bool auto_center_within_bounds = true;
    bool active = false;

    std::vector<std::vector<int>> edges;
    std::vector<glm::vec3> positions;
    std::vector<bool> pinned;
    std::vector<glm::dvec2> forces;
    std::tuple<double, double, double> last_results {0.0, 0.0, 0.0};

    sol::function callback;

    ForceLayoutSignal changed;
    ForceLayoutSignal stabilized;

    void emit_changed();
    void emit_stabilized();
    void refresh_center_from_bounds();
    glm::vec3 clamp_to_bounds(const glm::vec3& pos) const;
};
