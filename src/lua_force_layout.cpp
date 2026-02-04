#include <sol/sol.hpp>
#include <glm/glm.hpp>
#include <utility>

#include "force_layout.h"

namespace {

sol::table create_force_layout_table(sol::state_view lua)
{
    sol::table force_layout_table = lua.create_table();
    force_layout_table.new_usertype<ForceLayoutSignal>("ForceLayoutSignal",
        "connect", &ForceLayoutSignal::connect,
        "disconnect", sol::overload(
            [](ForceLayoutSignal& self, int id) { self.disconnect(id, false); },
            [](ForceLayoutSignal& self, int id, bool allowMissing) { self.disconnect(id, allowMissing); }
        ),
        "clear", &ForceLayoutSignal::clear,
        "size", &ForceLayoutSignal::size
    );

    struct PositionsView {
        ForceLayout* layout;
    };

    force_layout_table.new_usertype<PositionsView>("ForceLayoutPositionsView",
        sol::no_constructor,
        sol::meta_function::index, [](PositionsView& view, int i) -> glm::vec3& {
            if (!view.layout) {
                throw sol::error("ForceLayoutPositionsView has no layout");
            }
            if (i < 1) {
                throw sol::error("ForceLayoutPositionsView index out of range");
            }
            size_t index = static_cast<size_t>(i - 1);
            if (index >= view.layout->positions_size()) {
                throw sol::error("ForceLayoutPositionsView index out of range");
            }
            return view.layout->position_at(index);
        },
        sol::meta_function::length, [](PositionsView& view) {
            return view.layout ? view.layout->positions_size() : static_cast<size_t>(0);
        }
    );

    sol::usertype<ForceLayout> fl_type = force_layout_table.new_usertype<ForceLayout>("ForceLayout",
        sol::no_constructor,
        "spring-rest-length", &ForceLayout::spring_rest_length,
        "repulsive-force-constant", &ForceLayout::repulsive_force_constant,
        "spring-constant", &ForceLayout::spring_constant,
        "delta-t", &ForceLayout::delta_t,
        "center-force", &ForceLayout::center_force,
        "stabilized-max-displacement", &ForceLayout::stabilized_max_displacement,
        "stabilized-avg-displacement", &ForceLayout::stabilized_avg_displacement,
        "max-displacement-squared", &ForceLayout::max_displacement_squared,
        "update-interval", &ForceLayout::update_interval,
        "active", sol::property(&ForceLayout::is_active),
        "center-position", sol::property(&ForceLayout::get_center_position, &ForceLayout::set_center_position),
        "bounds", sol::property(&ForceLayout::get_bounds,
            static_cast<void (ForceLayout::*)(const std::pair<glm::vec3, glm::vec3>&)>(&ForceLayout::set_bounds)),
        "auto-center-within-bounds", sol::property(&ForceLayout::get_auto_center_within_bounds,
            &ForceLayout::set_auto_center_within_bounds),
        "node-count", sol::property(&ForceLayout::node_count),
        "positions", sol::property([](ForceLayout& self) { return PositionsView{&self}; })
    );

    fl_type.set_function("clear", &ForceLayout::clear);
    fl_type.set_function("add-node", &ForceLayout::add_node);
    fl_type.set_function("add-edge", &ForceLayout::add_edge);
    fl_type.set_function("set-position", &ForceLayout::set_position);
    fl_type.set_function("pin-node", &ForceLayout::pin_node);
    fl_type.set_function("step", &ForceLayout::step);
    fl_type.set_function("update", &ForceLayout::update);
    fl_type.set_function("start", sol::overload(
        [](ForceLayout& self) { self.start(); },
        [](ForceLayout& self, const sol::function& cb) { self.start(cb); }
    ));
    fl_type.set_function("cancel", &ForceLayout::cancel);
    fl_type.set_function("stop", &ForceLayout::stop);
    fl_type.set_function("run", sol::overload(
        [](ForceLayout& self) { self.run(); },
        [](ForceLayout& self, const sol::function& cb) { self.run(cb); }
    ));
    fl_type.set_function("until-stable", &ForceLayout::until_stable);
    fl_type.set_function("set-bounds", sol::overload(
        static_cast<void (ForceLayout::*)(const glm::vec3&, const glm::vec3&)>(&ForceLayout::set_bounds),
        static_cast<void (ForceLayout::*)(const std::pair<glm::vec3, glm::vec3>&)>(&ForceLayout::set_bounds)
    ));
    fl_type.set_function("get-bounds", &ForceLayout::get_bounds);
    fl_type.set_function("get-positions", [](ForceLayout& self) { return PositionsView{&self}; });
    fl_type.set_function("get-results", &ForceLayout::get_results);
    fl_type.set_function("set-center-position", &ForceLayout::set_center_position);
    fl_type["changed"] = sol::property(&ForceLayout::changed_signal);
    fl_type["stabilized"] = sol::property(&ForceLayout::stabilized_signal);

    force_layout_table.set_function("ForceLayout", sol::overload(
        []() { return ForceLayout(); },
        [](const glm::vec3& center, double springRestLength, double repulsiveForceConstant,
           double springConstant, double deltaT, double centerForce, double stabilizedMaxDisplacement,
           double stabilizedAvgDisplacement, double maxDisplacementSquared, double updateInterval) {
            return ForceLayout(center, springRestLength, repulsiveForceConstant, springConstant, deltaT,
                               centerForce, stabilizedMaxDisplacement, stabilizedAvgDisplacement,
                               maxDisplacementSquared, updateInterval);
        },
        [](const glm::vec3& center, double springRestLength, double repulsiveForceConstant,
           double springConstant, double deltaT, double centerForce, double stabilizedMaxDisplacement,
           double stabilizedAvgDisplacement, double maxDisplacementSquared, double updateInterval,
           const glm::vec3& minBounds, const glm::vec3& maxBounds, bool autoCenterWithinBounds) {
            return ForceLayout(center, springRestLength, repulsiveForceConstant, springConstant, deltaT,
                               centerForce, stabilizedMaxDisplacement, stabilizedAvgDisplacement,
                               maxDisplacementSquared, updateInterval, minBounds, maxBounds,
                               autoCenterWithinBounds);
        }
    ));
    return force_layout_table;
}

} // namespace

void lua_bind_force_layout(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("force-layout", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_force_layout_table(lua);
    });
}
