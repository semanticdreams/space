#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include <vector>
#include <unordered_map>
#include <cmath>
#include <random>
#include <omp.h>

namespace py = pybind11;

class ForceLayout {
public:
    int dimensions;
    double spring_rest_length;
    double repulsive_force_constant;
    double spring_constant;
    double delta_t;
    double center_force;
    std::vector<double> center_position;
    double max_displacement_squared;

    bool active = false;

    std::vector<std::vector<int>> edges;
    py::array_t<double> positions;
    std::vector<bool> pinned;

    ForceLayout(
                py::array_t<double> center_position_,
                int dimensions_=2,
                double spring_rest_length_=50,
                double repulsive_force_constant_=6250,
                double spring_constant_=1,
                double delta_t_=0.02,
                double center_force_=0.0001,
                double max_displacement_squared_=100.0)
        : dimensions(dimensions_),
          spring_rest_length(spring_rest_length_),
          repulsive_force_constant(repulsive_force_constant_),
          spring_constant(spring_constant_),
          delta_t(delta_t_),
          center_force(center_force_),
          max_displacement_squared(max_displacement_squared_) {
              auto buf = center_position_.unchecked<1>();
              center_position.resize(dimensions);
              for (int i = 0; i < dimensions; ++i) {
                  center_position[i] = buf(i);
              }

              clear();
    }

    void clear() {
        positions = py::array_t<double>(py::array_t<double>::ShapeContainer{0, dimensions});
        edges.clear();
    }

    int add_node(py::array_t<double> pos) {
        auto buf = positions.request();
        size_t n = buf.shape[0];

        py::array_t<double> new_positions(std::vector<ssize_t>{static_cast<ssize_t>(n + 1), static_cast<ssize_t>(dimensions)});


        auto r = new_positions.mutable_unchecked<2>();
        auto r_old = positions.unchecked<2>();

        for (size_t i = 0; i < n; ++i)
            for (int j = 0; j < dimensions; ++j)
                r(i, j) = r_old(i, j);

        auto pos_unchecked = pos.unchecked<1>();
        for (int j = 0; j < dimensions; ++j)
            r(n, j) = pos_unchecked(j);

        positions = new_positions;
        edges.emplace_back();

        pinned.push_back(false);  // not pinned by default

        return static_cast<int>(n);
    }

    void add_edge(int source, int target, bool mirror=true) {
        if (source >= edges.size() || target >= edges.size()) return;
        edges[source].push_back(target);
        if (mirror) edges[target].push_back(source);
    }

    void set_position(int idx, py::array_t<double> pos) {
        if (idx < 0 || idx >= positions.shape(0)) {
            throw std::out_of_range("Index out of bounds in set_position");
        }

        if (pos.ndim() != 1) {
            throw std::runtime_error("Position must be a 1D array");
        }

        auto pos_unchecked = pos.unchecked<1>();
        auto pos_buf = positions.mutable_unchecked<2>();

        for (int j = 0; j < dimensions; ++j) {
            pos_buf(idx, j) = pos_unchecked(j);
        }      
    }

    void pin_node(int idx, bool value = true) {
        if (idx >= 0 && idx < pinned.size()) {
            pinned[idx] = value;
        }
    }

    std::tuple<double, double, double> step(int num_iterations = 10) {
        double total, max_d;
        size_t n;

        for (int iter = 0; iter < num_iterations; ++iter) {
            auto pos = positions.mutable_unchecked<2>();
            n = pos.shape(0);
            std::vector<std::vector<double>> forces(n, std::vector<double>(dimensions, 0.0));

            // Repulsion
#pragma omp parallel for schedule(dynamic)
            for (int i = 0; i < n; ++i) {
                for (int j = i + 1; j < n; ++j) {
                    double dist_sq = 0.0;
                    std::vector<double> delta(dimensions);
                    for (int d = 0; d < dimensions; ++d) {
                        delta[d] = pos(i, d) - pos(j, d);
                        dist_sq += delta[d] * delta[d];
                    }

                    if (dist_sq == 0.0) {
                        // Random small jitter
                        for (int d = 0; d < dimensions; ++d) {
                            double jitter = ((rand() / double(RAND_MAX)) - 0.5) * 60.0;
#pragma omp atomic
                            forces[i][d] += jitter;
#pragma omp atomic
                            forces[j][d] -= jitter;
                        }
                        continue;
                    }

                    double dist = std::sqrt(dist_sq);
                    double force_mag = repulsive_force_constant / dist_sq;

                    for (int d = 0; d < dimensions; ++d) {
                        double f = force_mag * delta[d] / dist;
#pragma omp atomic
                        forces[i][d] += f;
#pragma omp atomic
                        forces[j][d] -= f;
                    }
                }
            }

            // Spring (edges)
            for (int i = 0; i < n; ++i) {
                for (int j : edges[i]) {
                    if (i < j) {
                        double dist = 0.0;
                        std::vector<double> delta(dimensions);
                        for (int d = 0; d < dimensions; ++d) {
                            delta[d] = pos(i, d) - pos(j, d);
                            dist += delta[d] * delta[d];
                        }
                        dist = std::sqrt(dist);
                        double force_mag = spring_constant * (dist - spring_rest_length);

                        for (int d = 0; d < dimensions; ++d) {
                            double f = force_mag * delta[d] / dist;
                            forces[i][d] -= f;
                            forces[j][d] += f;
                        }
                    }
                }
            }

            // Center force
            for (ssize_t i = 0; i < n; ++i) {
                for (ssize_t d = 0; d < dimensions; ++d) {
                    double diff = center_position[d] - pos(i, d);
                    double force = center_force * diff * std::abs(diff);
                    forces[i][d] += force;
                }
            }

            // Update positions
            total = 0, max_d = 0;
            for (int i = 0; i < n; ++i) {
                if (pinned[i]) continue;

                double disp_sq = 0.0;
                for (int d = 0; d < dimensions; ++d) {
                    double disp = delta_t * forces[i][d];
                    disp_sq += disp * disp;
                }

                double scale = 1.0;
                if (disp_sq > max_displacement_squared)
                    scale = std::sqrt(max_displacement_squared / disp_sq);

                double disp = 0.0;
                for (int d = 0; d < dimensions; ++d) {
                    double delta = delta_t * forces[i][d] * scale;
                    pos(i, d) += delta;
                    disp += delta * delta;
                }

                double dist = std::sqrt(disp);
                total += dist;
                if (dist > max_d) max_d = dist;
            }
        }

        return std::make_tuple(total, total / n, max_d);
    }

    py::array_t<double> get_positions() const {
        return positions;
    }
};

PYBIND11_MODULE(force_layout, m) {
    py::class_<ForceLayout>(m, "ForceLayout")
        .def(py::init<py::array_t<double>, int, double, double, double, double, double, double>(),
             py::arg("center_position"),
             py::arg("dimensions") = 2,
             py::arg("spring_rest_length") = 50,
             py::arg("repulsive_force_constant") = 6250,
             py::arg("spring_constant") = 1,
             py::arg("delta_t") = 0.02,
             py::arg("center_force") = 0.0001,
             py::arg("max_displacement_squared") = 100.0)
        .def("add_node", &ForceLayout::add_node)
        .def("add_edge", &ForceLayout::add_edge)
        .def("set_position", &ForceLayout::set_position)
        .def("pin_node", &ForceLayout::pin_node)
        .def("clear", &ForceLayout::clear)
        .def("step", &ForceLayout::step)
        .def("get_positions", &ForceLayout::get_positions)

        .def_readwrite("repulsive_force_constant", &ForceLayout::repulsive_force_constant)
        .def_readwrite("spring_rest_length", &ForceLayout::spring_rest_length)
        .def_readwrite("spring_constant", &ForceLayout::spring_constant)
        .def_readwrite("max_displacement_squared", &ForceLayout::max_displacement_squared)
        .def_readwrite("center_force", &ForceLayout::center_force)
        .def_readwrite("delta_t", &ForceLayout::delta_t)
        ;
}
