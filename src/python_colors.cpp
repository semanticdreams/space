#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <pybind11/complex.h>
#include <pybind11/numpy.h>
#include <pybind11/functional.h>
#include <pybind11/chrono.h>
#include <glm/glm.hpp>

#include "colors.h"

namespace py = pybind11;

py::dict create_color_swatch_py(const std::vector<float>& rgb) {
    if (rgb.size() != 3) {
        throw std::runtime_error("Expected 3-element RGB list.");
    }

    glm::vec3 color(rgb[0], rgb[1], rgb[2]);
    auto swatch = createColorSwatch(color);

    py::dict result;
    for (const auto& [key, vec] : swatch) {
        result[py::int_(key)] = py::make_tuple(vec.r, vec.g, vec.b, 1.0);
    }
    return result;
}

PYBIND11_MODULE(colors, m) {
    m.doc() = "Generate perceptual color swatches from base RGB color";
    m.def("create_color_swatch", &create_color_swatch_py, "Generate a color swatch from RGB",
          py::arg("rgb"));
}
