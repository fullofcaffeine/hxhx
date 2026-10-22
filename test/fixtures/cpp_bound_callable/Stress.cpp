// Observe generated code without editing it. Every allocation can collect;
// receiver/callable cycles must disappear when the program's local roots end.
#define main hxhx_fixture_main
#include "Main.cpp"
#undef main

// The loaded standard library retains nullary enum values: ValueType has seven,
// StackItem has CFunction, Encoding has two, and Error has three. Together with
// one program-storage allocation and SysTools.winMetaCharacters (also aliased
// by StringTools), these are the complete permanent roots.
// Keep this fixed inventory independent of the observed post-collection count.
constexpr std::size_t expectedPermanentAllocations = 1 + 7 + 1 + 2 + 3 + 1;

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  // No instance or callable may survive through its receiver/callable cycle.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != expectedPermanentAllocations) return 31;
  hxhx::managed::Heap second(0);
  hxhx_program_run(second);
  second.collect();
  if (second.rootCount() != 0 || second.staticRootCount() != 1 || second.liveCount() != expectedPermanentAllocations) return 32;
}
