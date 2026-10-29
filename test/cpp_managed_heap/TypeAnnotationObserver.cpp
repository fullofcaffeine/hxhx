// Read the generated program's state without modifying its source.
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
  // The static plan orders these slots by field identity, not declaration order.
  std::cout << state->field_4.read().asInteger() << '\n'; // plain
  std::cout << state->field_1.read().asInteger() << '\n'; // converted
  std::cout << state->field_0.read().asInteger() << '\n';
  std::cout << state->field_5.read().asInteger() << '\n';
  if (heap.liveCount() != 1 || heap.staticRootCount() != 1)
    throw std::runtime_error("annotation retained temporary storage");
}
