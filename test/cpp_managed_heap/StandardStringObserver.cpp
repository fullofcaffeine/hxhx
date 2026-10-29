#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include <stdexcept>

// The real Haxe 4.3.7 dependency closure retains one program storage object,
// thirteen enum singletons (ValueType: 7, StackItem: 1, Encoding: 2, Error: 3), and the shared
// StringTools character array. Conversion must leave no additional live values
// or temporary roots after collection. These source-owned objects are absent
// from the smaller local-assignment fixture's one-object expectation.
int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 15)
    throw std::runtime_error("standard conversion retained unexpected storage");
}
