#include <sol/sol.hpp>
#include <tree_sitter/api.h>
#include <string>
#include <memory>
#include <vector>
#include <cstring>

extern "C" const TSLanguage *tree_sitter_cpp();
extern "C" const TSLanguage *tree_sitter_fennel();

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

namespace {

sol::table create_tree_sitter_table(sol::state_view lua)
{
    sol::table ts_module = lua.create_table();

    ts_module.set_function("parse", [](const std::string& code, sol::object opts) -> LuaTSTree {
        UniqueParser parser(ts_parser_new());
        const TSLanguage *lang = tree_sitter_cpp();

        if (opts.is<sol::table>()) {
            sol::table t = opts.as<sol::table>();
            sol::object lang_opt = t["language"];
            if (lang_opt.valid()) {
                std::string lang_str = lang_opt.as<std::string>();
                if (lang_str == "cpp" || lang_str == ":cpp") {
                    lang = tree_sitter_cpp();
                } else if (lang_str == "fennel" || lang_str == ":fennel") {
                    lang = tree_sitter_fennel();
                } else {
                    throw sol::error("tree-sitter.parse unsupported language: " + lang_str);
                }
            }
        }

        ts_parser_set_language(parser.get(), lang);
        TSTree *tree = ts_parser_parse_string(parser.get(), nullptr, code.c_str(), code.size());

        return LuaTSTree(tree);
    });

    ts_module.new_usertype<LuaTSNode>("TSNode",
        "type", &LuaTSNode::type,
        "child-count", &LuaTSNode::child_count,
        "child", &LuaTSNode::child,
        "start-byte", &LuaTSNode::start_byte,
        "end-byte", &LuaTSNode::end_byte,
        "start-point", [](const LuaTSNode& self, sol::this_state state) -> sol::table {
            TSPoint pt = ts_node_start_point(self.node);
            sol::state_view lua(state);
            sol::table t = lua.create_table();
            t["row"] = pt.row;
            t["column"] = pt.column;
            return t;
        },
        "end-point", [](const LuaTSNode& self, sol::this_state state) -> sol::table {
            TSPoint pt = ts_node_end_point(self.node);
            sol::state_view lua(state);
            sol::table t = lua.create_table();
            t["row"] = pt.row;
            t["column"] = pt.column;
            return t;
        },
        "is-null", &LuaTSNode::is_null,
        "sexpr", &LuaTSNode::sexpr
    );

    ts_module.new_usertype<LuaTSTree>("TSTree",
        "root", &LuaTSTree::root
    );
    return ts_module;
}

} // namespace

void lua_bind_tree_sitter(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("tree-sitter", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_tree_sitter_table(lua);
    });
}
