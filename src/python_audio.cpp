#include <pybind11/pybind11.h>

#include "audio.h"

namespace py = pybind11;

PYBIND11_MODULE(audio, m) {
    m.doc() = "Audio Module";

    py::class_<Audio>(m, "Audio", py::module_local())
        .def("load_sound", &Audio::loadSound, py::arg("name"), py::arg("filepath"))
        .def("play_sound", [](Audio& self, const std::string& name, std::tuple<float, float, float> pos, bool loop, bool positional) {
            glm::vec3 p{std::get<0>(pos), std::get<1>(pos), std::get<2>(pos)};
            return self.playSound(name, p, loop, positional);
        }, py::arg("name"), py::arg("position"), py::arg("loop") = false, py::arg("positional") = true)

        .def("set_listener_position", [](Audio& self, std::tuple<float, float, float> pos) {
            self.setListenerPosition(glm::vec3{std::get<0>(pos), std::get<1>(pos), std::get<2>(pos)});
        })

        .def("set_listener_orientation", [](Audio& self,
                std::tuple<float, float, float> forward,
                std::tuple<float, float, float> up) {
            self.setListenerOrientation(
                glm::vec3{std::get<0>(forward), std::get<1>(forward), std::get<2>(forward)},
                glm::vec3{std::get<0>(up), std::get<1>(up), std::get<2>(up)}
            );
        })

        .def("set_source_position", [](Audio& self, uint32_t source_id, std::tuple<float, float, float> pos) {
            self.setSourcePosition(source_id, glm::vec3{std::get<0>(pos), std::get<1>(pos), std::get<2>(pos)});
        })

        .def("stop_sound", &Audio::stopSound)
        .def("waitForSoundToFinish", &Audio::waitForSoundToFinish)
            ;
}
