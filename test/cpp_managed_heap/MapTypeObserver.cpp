// Run the unchanged generated program with collection before every allocation.
// Only the program's static graph may survive after its local roots leave.
#define main generated_main
#include "src/Main.cpp"
#undef main
#include <cstdio>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  if (heap.rootCount() != 0) {
    std::fprintf(stderr, "Map observer retained %zu temporary roots\n", heap.rootCount());
    return 1;
  }
  heap.collect();
  // The real provider closure includes Type through EnumValueMap. Startup keeps
  // seven ValueType singletons: TNull, TInt, TFloat, TBool, TObject, TFunction,
  // TUnknown. StackItem, Encoding, and Error contribute another six singletons.
  // Those 13 values, one shared escape-character array, and program storage
  // account for exactly 15 live nodes after collection.
  // No fixture Map or temporary Array belongs to that persistent graph.
  if (heap.staticRootCount() != 1 || heap.liveCount() != 15) {
    std::fprintf(stderr, "Map observer expected 1 static root and 15 live nodes; got %zu and %zu\n",
                 heap.staticRootCount(), heap.liveCount());
    return 2;
  }
  return 0;
}
