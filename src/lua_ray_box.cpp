#include <sol/sol.hpp>

#include <algorithm>
#include <cmath>
#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtx/quaternion.hpp>
#include <limits>
#include <optional>

namespace {

std::tuple<bool, sol::optional<glm::vec3>, sol::optional<float>> ray_box_intersection(const sol::table& ray,
    const sol::table& bounds)
{
    sol::optional<glm::vec3> origin_opt = ray.get<sol::optional<glm::vec3>>("origin");
    sol::optional<glm::vec3> direction_opt = ray.get<sol::optional<glm::vec3>>("direction");
    if (!origin_opt || !direction_opt) {
        return {false, sol::optional<glm::vec3>(), sol::optional<float>()};
    }

    const glm::vec3 origin = origin_opt.value();
    const glm::vec3 direction = direction_opt.value();

    const glm::quat rotation = bounds.get<sol::optional<glm::quat>>("rotation").value_or(glm::quat(1.0f, 0.0f, 0.0f, 0.0f));
    const glm::vec3 position = bounds.get<sol::optional<glm::vec3>>("position").value_or(glm::vec3(0.0f));
    const glm::quat inverse_rotation = glm::inverse(rotation);

    const glm::vec3 local_origin = inverse_rotation * (origin - position);
    const glm::vec3 local_direction = inverse_rotation * direction;

    const glm::vec3 min_bounds = bounds.get<sol::optional<glm::vec3>>("min-bounds").value_or(glm::vec3(0.0f));
    sol::optional<glm::vec3> size_opt = bounds.get<sol::optional<glm::vec3>>("size");
    sol::optional<glm::vec3> max_opt = bounds.get<sol::optional<glm::vec3>>("max-bounds");
    const glm::vec3 max_bounds = max_opt.has_value() ? max_opt.value() : (size_opt.has_value() ? min_bounds + size_opt.value() : min_bounds);

    const double epsilon = bounds.get<sol::optional<double>>("epsilon").value_or(1e-6);

    double tmin = -std::numeric_limits<double>::infinity();
    double tmax = std::numeric_limits<double>::infinity();

    for (int axis = 0; axis < 3; ++axis) {
        const double origin_component = static_cast<double>(local_origin[axis]);
        const double direction_component = static_cast<double>(local_direction[axis]);
        const double min_bound = static_cast<double>(min_bounds[axis]);
        const double max_bound = static_cast<double>(max_bounds[axis]);

        if (std::abs(direction_component) > epsilon) {
            const double t1 = (min_bound - origin_component) / direction_component;
            const double t2 = (max_bound - origin_component) / direction_component;
            const double entry = std::min(t1, t2);
            const double exit = std::max(t1, t2);

            tmin = std::max(tmin, entry);
            tmax = std::min(tmax, exit);
            if (tmin > tmax) {
                return {false, sol::optional<glm::vec3>(), sol::optional<float>()};
            }
        } else if (origin_component < min_bound || origin_component > max_bound) {
            return {false, sol::optional<glm::vec3>(), sol::optional<float>()};
        }
    }

    if (tmax < 0.0) {
        return {false, sol::optional<glm::vec3>(), sol::optional<float>()};
    }

    const double t = tmin > 0.0 ? tmin : tmax;
    if (t < 0.0) {
        return {false, sol::optional<glm::vec3>(), sol::optional<float>()};
    }

    const glm::vec3 scaled_direction = local_direction * static_cast<float>(t);
    const glm::vec3 intersection_local = local_origin + scaled_direction;
    const glm::vec3 rotated_point = rotation * intersection_local;
    const glm::vec3 intersection_world = rotated_point + position;
    const float distance = glm::length(intersection_world - origin);

    return {true, sol::optional<glm::vec3>(intersection_world), sol::optional<float>(distance)};
}

} // namespace

void lua_bind_ray_box(sol::state& lua)
{
    lua["package"]["preload"]["ray-box"] = [](sol::this_state ts) {
        sol::state_view lua_state(ts);
        sol::table module = lua_state.create_table();
        module["ray-box-intersection"] = &ray_box_intersection;
        return module;
    };
}
