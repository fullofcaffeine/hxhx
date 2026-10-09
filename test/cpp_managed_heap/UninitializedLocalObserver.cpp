#define main generated_main
#include HXHX_LOCAL_PROGRAM
#undef main
#include <stdexcept>
#include <string>

// Run the emitted source under forced collection. The two negative programs
// must fail at the checked storage read, before a fabricated value can escape.
int main() {
  hxhx::managed::Heap heap(0);
  const std::string expected = HXHX_UNASSIGNED_DIAGNOSTIC;
  bool rejected = false;
  try {
    hxhx_program_run(heap);
  } catch (const std::logic_error& error) {
    if (expected.empty() || expected != error.what()) throw;
    rejected = true;
  }
  if (rejected != !expected.empty())
    throw std::runtime_error("unassigned local observation did not match its contract");
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("local assignment retained temporary storage");
}
