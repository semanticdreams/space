add_library(sqlite3 STATIC
    sqlite3.c
)

target_include_directories(sqlite3 PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_compile_options(sqlite3 PRIVATE
    -Wno-return-local-addr
)

add_library(lsqlite3 STATIC
    lsqlite3.c
)

target_include_directories(lsqlite3 PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    $<TARGET_PROPERTY:lua,INTERFACE_INCLUDE_DIRECTORIES>
)

target_link_libraries(lsqlite3 PUBLIC
    sqlite3
    lua
)
