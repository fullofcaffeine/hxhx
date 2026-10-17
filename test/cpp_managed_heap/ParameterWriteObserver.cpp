#include HXHX_LOCAL_PROGRAM
#include <stdexcept>

// Haxe owns the assignments. This observer supplies exact native ABI inputs and
// checks their returned values while forcing collection through closure calls.
int main() {
  hxhx::managed::Heap heap(0);
  const double original = 1.25;
  if (generated_replace(heap, original, 2.5) != 2.5 || original != 1.25)
    throw std::runtime_error("Float parameter assignment changed caller storage");
  if (generated_throughClosure(heap, original, -4.5) != -4.5)
    throw std::runtime_error("Float closure parameter assignment changed its result");
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 0 || heap.liveCount() != 0)
    throw std::runtime_error("parameter writes retained roots or allocations");
}
