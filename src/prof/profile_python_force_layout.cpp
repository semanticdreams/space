#include <iostream>
#include <pybind11/embed.h>
#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include <random>
#include <valgrind/callgrind.h>

#include "../python_force_layout.h"

namespace py = pybind11;

void profile_force_layout_step() {
    int num_nodes = 100;
    int dimensions = 2;

    // Create center position
    py::array_t<double> center({dimensions});
    auto center_mut = center.mutable_unchecked<1>();
    for (int i = 0; i < dimensions; ++i)
        center_mut(i) = 0.0;

    // Create layout
    ForceLayout layout(center);

    // Random number generator
    std::mt19937 rng(42);  // fixed seed for repeatability
    std::uniform_real_distribution<double> dist(-100.0, 100.0);

    // Add nodes
    for (int i = 0; i < num_nodes; ++i) {
        py::array_t<double> pos({dimensions});
        auto pos_mut = pos.mutable_unchecked<1>();
        for (int d = 0; d < dimensions; ++d) {
            pos_mut(d) = dist(rng);
        }
        layout.add_node(pos);
    }

    // Add random edges
    std::uniform_int_distribution<int> index_dist(0, num_nodes - 1);
    for (int i = 0; i < num_nodes * 2; ++i) { // roughly 2 edges per node
        int a = index_dist(rng);
        int b = index_dist(rng);
        if (a != b) {
            layout.add_edge(a, b);
        }
    }

    std::cout << "starting step profiling..." << std::endl;

	CALLGRIND_START_INSTRUMENTATION;

    layout.step(10);

	CALLGRIND_STOP_INSTRUMENTATION;
}


int main() {
    py::scoped_interpreter guard{};
    profile_force_layout_step();
    return 0;
}

/*
Add to CMakeLists.txt:

set(CMAKE_BUILD_TYPE Debug)
add_executable(profile_python_force_layout
    src/prof/profile_python_force_layout.cpp
    src/python_force_layout.cpp
)
target_link_libraries(profile_python_force_layout
    Python3::Python
    glm::glm
    OpenMP::OpenMP_CXX
)
target_compile_options(profile_python_force_layout PRIVATE -g)
target_link_options(profile_python_force_layout PRIVATE -g)

Run:

cd build && valgrind --tool=callgrind --instr-atstart=no ./profile_python_force_layout
*/
