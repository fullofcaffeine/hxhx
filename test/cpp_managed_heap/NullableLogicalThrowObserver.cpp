// Observe exception identity and root cleanup through the normal generated runner.
#define main generated_main
#include "Main.cpp"
#undef main
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  bool caught = false;
  try {
    hxhx_program_run(heap);
  } catch (const hxhx::managed::ThrownValue& error) {
    heap.collect();
    if (error.value().kind() != hxhx::managed::ValueKind::String ||
        error.value().asString() != "selected operand")
      throw std::runtime_error("logical operand threw the wrong value");
    caught = true;
  }
  if (!caught)
    throw std::runtime_error("selected logical operand did not throw");
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("logical exception retained temporary roots or values");
}
