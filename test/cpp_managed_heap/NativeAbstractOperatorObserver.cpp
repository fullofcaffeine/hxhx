// Inspect original generated storage after the normal program runner completes.
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
  // Slots follow sorted field identity: calls, inverted, maximum, minimum,
  // negativeOne, result, zero. The observation order follows the Haxe oracle.
  std::cout << state->field_5.read().asInteger() << '\n';
  std::cout << state->field_0.read().asInteger() << '\n';
  std::cout << state->field_3.read().asInteger() << '\n';
  std::cout << state->field_2.read().asInteger() << '\n';
  std::cout << state->field_6.read().asInteger() << '\n';
  std::cout << state->field_4.read().asInteger() << '\n';
  std::cout << std::boolalpha << state->field_1.read().asBoolean() << '\n';
  if (heap.liveCount() != 1 || heap.staticRootCount() != 1)
    throw std::runtime_error("abstract operator retained temporary storage");
}
