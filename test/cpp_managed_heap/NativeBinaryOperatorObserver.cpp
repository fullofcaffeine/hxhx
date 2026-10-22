// Observe the original generated program after its normal startup and entry point.
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
  // Slots use sorted identities: compound, effects, equal, less, mixed, negated, sum.
  std::cout << std::boolalpha << state->field_3.read().asBoolean() << '\n';
  std::cout << state->field_6.read().asInteger() << '\n';
  std::cout << state->field_4.read().asInteger() << '\n';
  std::cout << state->field_0.read().asInteger() << '\n';
  std::cout << state->field_2.read().asBoolean() << '\n';
  std::cout << state->field_5.read().asInteger() << '\n';
  std::cout << state->field_1.read().asInteger() << '\n';
  if (heap.liveCount() != 1 || heap.staticRootCount() != 1)
    throw std::runtime_error("binary operator retained temporary storage");
}
