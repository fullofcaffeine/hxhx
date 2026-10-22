// Inspect the normal runner after collection; slots follow sorted Main field names.
#define main generated_main
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
  std::cout << state->field_1.read().asInteger() << '\n';
  std::cout << state->field_2.read().asInteger() << '\n';
  std::cout << state->field_3.read().asInteger() << '\n';
  std::cout << state->field_4.read().asInteger() << '\n';
  std::cout << state->field_5.read().asInteger() << '\n';
  std::cout << state->field_6.read().asInteger() << '\n';
  std::cout << state->field_7.read().asInteger() << '\n';
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("property update retained its temporary receiver");
}
