#include <sol/sol.hpp>
#include <tree_sitter/api.h>
#include <string>
#include <memory>
#include <vector>
#include <cstring>

extern "C" const TSLanguage *tree_sitter_cpp();

// Smart deleters
struct TSParserDeleter {
    void operator()(TSParser *parser) const { ts_parser_delete(parser); }
};

struct TSTreeDeleter {
    void operator()(TSTree *tree) const { ts_tree_delete(tree); }
};

using UniqueParser = std::unique_ptr<TSParser, TSParserDeleter>;
using UniqueTree = std::unique_ptr<TSTree, TSTreeDeleter>;

// Wrapper for TSNode
struct LuaTSNode {
    TSNode node;

    LuaTSNode(TSNode n) : node(n) {}

    std::string type() const {
        return ts_node_type(node);
    }

    uint32_t child_count() const {
        return ts_node_child_count(node);
    }

    LuaTSNode child(uint32_t index) const {
        return LuaTSNode(ts_node_child(node, index));
    }

    uint32_t start_byte() const {
        return ts_node_start_byte(node);
    }

    uint32_t end_byte() const {
        return ts_node_end_byte(node);
    }

    bool is_null() const {
        return ts_node_is_null(node);
    }

    std::string sexpr() const {
        return ts_node_string(node);
    }
};

// Wrapper for TSTree (exposed only through root)
struct LuaTSTree {
    UniqueTree tree;

    LuaTSTree(TSTree *t) : tree(t) {}

    LuaTSNode root() const {
        return LuaTSNode(ts_tree_root_node(tree.get()));
    }
};

// Binding function
void lua_bind_tree_sitter(sol::state& lua) {
    sol::table ts_module = lua.create_table();

    ts_module.set_function("parse", [](const std::string& code) -> LuaTSTree {
        UniqueParser parser(ts_parser_new());
        ts_parser_set_language(parser.get(), tree_sitter_cpp());

        TSTree *tree = ts_parser_parse_string(parser.get(), nullptr, code.c_str(), code.size());

        return LuaTSTree(tree);  // Returned as userdata
    });

    lua.new_usertype<LuaTSNode>("TSNode",
        "type", &LuaTSNode::type,
        "child_count", &LuaTSNode::child_count,
        "child", &LuaTSNode::child,
        "start_byte", &LuaTSNode::start_byte,
        "end_byte", &LuaTSNode::end_byte,
        "is_null", &LuaTSNode::is_null,
        "sexpr", &LuaTSNode::sexpr
    );

    lua.new_usertype<LuaTSTree>("TSTree",
        "root", &LuaTSTree::root
    );

    lua["tree_sitter"] = ts_module;
}
