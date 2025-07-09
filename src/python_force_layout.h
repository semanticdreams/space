#pragma once

#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include <vector>
#include <glm/glm.hpp>
#include <tuple>

namespace py = pybind11;

class ForceLayout {
public:
    double spring_rest_length;
    double repulsive_force_constant;
    double spring_constant;
    double delta_t;
    double center_force;
	glm::dvec2 center_position;
    double max_displacement_squared;

    bool active = false;

    std::vector<std::vector<int>> edges;
	std::vector<glm::dvec2> positions;
    std::vector<bool> pinned;
    std::vector<glm::dvec2> forces;

    ForceLayout(
        py::array_t<double> center_position_,
        double spring_rest_length_ = 50,
        double repulsive_force_constant_ = 6250,
        double spring_constant_ = 1,
        double delta_t_ = 0.02,
        double center_force_ = 0.0001,
        double max_displacement_squared_ = 100.0);

    void clear();
    int add_node(py::array_t<double> pos);
    void add_edge(int source, int target, bool mirror = true);
    void set_position(int idx, py::array_t<double> pos);
    void pin_node(int idx, bool value = true);
    std::tuple<double, double, double> step(int num_iterations = 10);
    py::array_t<double> get_positions() const;
};
