# external/tree-sitter/CMakeLists.txt
cmake_minimum_required(VERSION 3.15)

project(tree_sitter LANGUAGES C CXX)

# Core Tree-sitter C library
add_library(tree_sitter_core STATIC
    core/tree_sitter/lib.c
)

target_include_directories(tree_sitter_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Tree-sitter C++ grammar
add_library(tree_sitter_cpp STATIC
    cpp/parser.c
    cpp/scanner.c
)

add_library(tree_sitter_python STATIC
    python/parser.c
    python/scanner.c
)

add_library(tree_sitter_fennel STATIC
    fennel/parser.c
    fennel/scanner.c
)

add_library(tree_sitter_javascript STATIC
    javascript/parser.c
    javascript/scanner.c
)

target_include_directories(tree_sitter_cpp PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/core
    ${CMAKE_CURRENT_SOURCE_DIR}/core/tree_sitter
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/cpp
)

target_include_directories(tree_sitter_python PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/core
    ${CMAKE_CURRENT_SOURCE_DIR}/core/tree_sitter
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/python
)

target_include_directories(tree_sitter_fennel PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/core
    ${CMAKE_CURRENT_SOURCE_DIR}/core/tree_sitter
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/fennel
)

target_include_directories(tree_sitter_javascript PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/core
    ${CMAKE_CURRENT_SOURCE_DIR}/core/tree_sitter
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/javascript
)

# Link grammar with core
target_link_libraries(tree_sitter_cpp PUBLIC tree_sitter_core)
target_link_libraries(tree_sitter_python PUBLIC tree_sitter_core)
target_link_libraries(tree_sitter_fennel PUBLIC tree_sitter_core)
target_link_libraries(tree_sitter_javascript PUBLIC tree_sitter_core)
