#include <pybind11/pybind11.h>

#include "globals.h"
#include "asset_manager.h"

namespace py = pybind11;


int add(int a, int b) {
    return a + b;
}

void quit() {
    engine.quit();
}

PYBIND11_MODULE(space, m) {
    m.def("add", &add, "A function that adds two numbers");

    m.def("getAssetPath", &AssetManager::getAssetPath);
    m.def("quit", &quit);

    m.def("glClearColor", [](float r, float g, float b, float a) {
        glClearColor(r, g, b, a);
    });
}
