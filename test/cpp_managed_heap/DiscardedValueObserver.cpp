// Observe the authored source through its normal generated program runner.
#define main generated_process_entry
#include "Main.cpp"
#undef main
#include <iostream>
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  const auto state = heap.requireStatic<hxhx_statics_program>();
  std::cout << state->field_0.read().asInteger() << '\n';
  if (heap.liveCount() != 1 || heap.staticRootCount() != 1)
    throw std::runtime_error("discarded values retained temporary storage");
  hxhx::managed::Heap independent(0);
  hxhx_program_run(independent);
  if (independent.requireStatic<hxhx_statics_program>()->field_0.read().asInteger() != 1234)
    throw std::runtime_error("discarded operand effects leaked across heaps");
}
