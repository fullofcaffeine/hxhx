// Execute the generated source with collection before every allocation.
#define main generated_main
#include "src/Main.cpp"
#undef main
#include <cstdio>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  // Real EnumValueMap dependencies include Type's seven ValueType singletons.
  // StackItem, Encoding, and Error contribute six more. The fixture adds three
  // Key singletons; the shared escape-character array and program storage bring
  // the permanent graph to exactly 18 nodes. No temporary Map may survive.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 18) {
    std::fprintf(stderr, "enum Map expected 0 roots, 1 static root, and 18 live nodes; got %zu, %zu, and %zu\n",
                 heap.rootCount(), heap.staticRootCount(), heap.liveCount());
    return 1;
  }
}
