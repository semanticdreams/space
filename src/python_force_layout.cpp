#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include <vector>
#include <unordered_map>
#include <cmath>
#include <glm/glm.hpp>
#include <random>
#include <omp.h>

#include "python_force_layout.h"

ForceLayout::ForceLayout(
		py::array_t<double> center_position_,
		double spring_rest_length_,
		double repulsive_force_constant_,
		double spring_constant_,
		double delta_t_,
		double center_force_,
		double max_displacement_squared_)
	: spring_rest_length(spring_rest_length_),
	repulsive_force_constant(repulsive_force_constant_),
	spring_constant(spring_constant_),
	delta_t(delta_t_),
	center_force(center_force_),
	max_displacement_squared(max_displacement_squared_) {

		auto buf = center_position_.unchecked<1>();
		center_position = glm::dvec2(buf[0], buf[1]);

		clear();
	}

void ForceLayout::clear() {
	positions.clear();
	edges.clear();
	pinned.clear();
	forces.clear();
}

int ForceLayout::add_node(py::array_t<double> pos) {
	auto idx = positions.size();

	auto buf = pos.request();
	double* ptr = static_cast<double*>(buf.ptr);
	glm::dvec2 vec(ptr[0], ptr[1]);
	positions.push_back(vec);

	edges.emplace_back();
	pinned.push_back(false);
	forces.push_back(glm::dvec2(0.0));

	return idx;
}

void ForceLayout::add_edge(int source, int target, bool mirror) {
	if (source >= edges.size() || target >= edges.size()) return;
	edges[source].push_back(target);
	if (mirror) edges[target].push_back(source);
}

void ForceLayout::set_position(int idx, py::array_t<double> pos) {
	auto buf = pos.request();
	double* ptr = static_cast<double*>(buf.ptr);
	positions[idx] = glm::dvec2(ptr[0], ptr[1]);
}

void ForceLayout::pin_node(int idx, bool value) {
	if (idx >= 0 && idx < pinned.size()) {
		pinned[idx] = value;
	}
}

std::tuple<double, double, double> ForceLayout::step(int num_iterations) {
	double total = 0.0, max_d = 0.0;
	size_t n = positions.size();

	// Preallocate temp variables
	glm::dvec2 pi, pj, delta, f;
	glm::dvec2 jitter, diff, center_force_vec, disp;

	// Auto-center
	center_position.x = 0; center_position.y = 0;
	for (size_t i = 0; i < n; ++i) {
		center_position += glm::dvec2(positions[i].x, positions[i].y);
	}
	center_position /= static_cast<double>(n);

	for (int iter = 0; iter < num_iterations; ++iter) {
		std::memset(forces.data(), 0, n * sizeof(glm::dvec2));

#pragma omp parallel for private(pi, pj, delta, f, jitter) schedule(dynamic)
		for (int i = 0; i < static_cast<int>(n); ++i) {
			pi.x = positions[i].x;
			pi.y = positions[i].y;

			for (int j = i + 1; j < static_cast<int>(n); ++j) {
				pj.x = positions[j].x;
				pj.y = positions[j].y;
				delta = pi - pj;
				double dist_sq = glm::dot(delta, delta);

				if (dist_sq == 0.0) {
					jitter.x = ((rand() / double(RAND_MAX)) - 0.5) * 60.0;
					jitter.y = ((rand() / double(RAND_MAX)) - 0.5) * 60.0;
#pragma omp atomic
					forces[i].x += jitter.x;
#pragma omp atomic
					forces[i].y += jitter.y;
#pragma omp atomic
					forces[j].x -= jitter.x;
#pragma omp atomic
					forces[j].y -= jitter.y;
					continue;
				}

				double dist = std::sqrt(dist_sq);
				double force_mag = repulsive_force_constant / dist_sq;
				f = force_mag * (delta / dist);

#pragma omp atomic
				forces[i].x += f.x;
#pragma omp atomic
				forces[i].y += f.y;
#pragma omp atomic
				forces[j].x -= f.x;
#pragma omp atomic
				forces[j].y -= f.y;
			}
		}

#pragma omp parallel for private(pi, pj, delta, f) schedule(dynamic)
		for (int i = 0; i < static_cast<int>(n); ++i) {
			pi.x = positions[i].x;
			pi.y = positions[i].y;

			for (int j : edges[i]) {
				if (i < j) {
					pj.x = positions[j].x;
					pj.y = positions[j].y;
					delta = pi - pj;
					double dist = glm::length(delta);
					if (dist == 0.0) continue;

					double force_mag = spring_constant * (dist - spring_rest_length);
					f = force_mag * (delta / dist);

#pragma omp atomic
					forces[i].x -= f.x;
#pragma omp atomic
					forces[i].y -= f.y;
#pragma omp atomic
					forces[j].x += f.x;
#pragma omp atomic
					forces[j].y += f.y;
				}
			}
		}

#pragma omp parallel for private(diff, center_force_vec) schedule(static)
		for (size_t i = 0; i < n; ++i) {
			diff = center_position - glm::dvec2(positions[i].x, positions[i].y);
			center_force_vec = center_force * diff * glm::abs(diff);
#pragma omp atomic
			forces[i].x += center_force_vec.x;
#pragma omp atomic
			forces[i].y += center_force_vec.y;
		}

		total = 0.0;
		max_d = 0.0;

#pragma omp parallel for private(disp, delta) reduction(+:total) reduction(max:max_d)
		for (size_t i = 0; i < n; ++i) {
			if (pinned[i]) continue;

			disp = delta_t * forces[i];
			double disp_sq = glm::dot(disp, disp);
			double scale = 1.0;

			if (disp_sq > max_displacement_squared)
				scale = std::sqrt(max_displacement_squared / disp_sq);

			delta = disp * scale;
			positions[i].x += delta.x;
			positions[i].y += delta.y;

			double dist = glm::length(delta);
			total += dist;
			if (dist > max_d) max_d = dist;
		}
	}

	return std::make_tuple(total, total / n, max_d);
}

py::array_t<double> ForceLayout::get_positions() const {
	size_t n = positions.size();

    // Create a 2D array of shape (n, 2)
    py::array_t<double> result({n, static_cast<size_t>(2)});

    auto r = result.mutable_unchecked<2>();  // 2D unchecked access

    for (size_t i = 0; i < n; ++i) {
        r(i, 0) = positions[i].x;
        r(i, 1) = positions[i].y;
    }

    return result;
}

PYBIND11_MODULE(force_layout, m) {
    py::class_<ForceLayout>(m, "ForceLayout")
        .def(py::init<py::array_t<double>, double, double, double, double, double, double>(),
                py::arg("center_position"),
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
