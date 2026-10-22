// Observe the original runner with collection before every managed allocation.
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
  // Main's source fields use alphabetical order, matching OracleMain's observer.
  std::cout << state->field_0.read().asInteger() << '\n';
  std::cout << state->field_1.read().asInteger() << '\n';
  std::cout << state->field_2.read().asInteger() << '\n';
  std::cout << state->field_3.read().asInteger() << '\n';
  std::cout << state->field_4.read().asInteger() << '\n';
  std::cout << state->field_5.read().asInteger() << '\n';
  std::cout << state->field_6.read().asInteger() << '\n';
  std::cout << state->field_7.read().asInteger() << '\n';
  std::cout << state->field_8.read().asInteger() << '\n';
  std::cout << state->field_9.read().asInteger() << '\n';
  std::cout << state->field_10.read().asInteger() << '\n';
  std::cout << state->field_11.read().asInteger() << '\n';
  std::cout << state->field_12.read().asInteger() << '\n';
  std::cout << state->field_13.read().asInteger() << '\n';
  std::cout << state->field_14.read().asInteger() << '\n';
  std::cout << state->field_15.read().asInteger() << '\n';
  std::cout << state->field_16.read().asInteger() << '\n';
  std::cout << state->field_17.read().asInteger() << '\n';
  std::cout << state->field_18.read().asInteger() << '\n';
  // This Array provider graph declares no retained enum constants. Only the
  // program's scalar storage remains; all receivers and arrays must be collected.
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("inline unary update retained a temporary receiver or array");
}
