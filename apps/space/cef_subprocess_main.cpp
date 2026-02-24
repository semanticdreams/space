#include <iostream>

#include "cef_runtime.h"

int main(int argc, char** argv)
{
    int exit_code = cef_runtime::maybe_execute_subprocess(argc, argv);
    if (exit_code >= 0) {
        return exit_code;
    }
    std::cerr << "space_cef_helper was started without a CEF subprocess role\n";
    return 1;
}
