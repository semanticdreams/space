local tree = tree_sitter.parse([[
int main() {
    return 0;
}
]])

local root = tree:root()
print("Root type:", root:type())
print("S-expression:", root:sexpr())

for i = 0, root:child_count() - 1 do
  local child = root:child(i)
  print("Child:", child:type(), child:start_byte(), child:end_byte())
end
