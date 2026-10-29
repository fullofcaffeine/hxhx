// Observe generated code without modifying it. Every allocation may collect,
// including binding push on an array whose elements contain another callable.
#define main hxhx_fixture_main
#include "Main.cpp"
#undef main

// Independent provider inventory: one program store; ValueType (7), StackItem
// (1), Encoding (2), Error (3); and the shared SysTools.winMetaCharacters array.
constexpr std::size_t expectedPermanentAllocations = 1 + 7 + 1 + 2 + 3 + 1;

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != expectedPermanentAllocations) return 31;
  hxhx::managed::Heap second(0);
  hxhx_program_run(second);
  second.collect();
  if (second.rootCount() != 0 || second.staticRootCount() != 1 || second.liveCount() != expectedPermanentAllocations) return 32;
}
