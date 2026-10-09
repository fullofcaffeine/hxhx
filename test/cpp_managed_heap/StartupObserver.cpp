// Give the generated process entry another symbol so this independent observer
// can call the very same program runner with an inspectable heap. No artifact is edited.
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
  std::cout << state->field_4.read().asInteger() << '\n';
  std::cout << state->field_5.read().asInteger() << '\n';
  std::cout << state->field_6.read().asInteger() << '\n';
  std::cout << state->field_7.read().asInteger() << '\n';
  std::cout << state->field_1.read().asInteger() << '\n';
  std::cout << state->field_2.read().asInteger() << '\n';
  std::cout << state->field_3.read().asInteger() << '\n';
  if (heap.liveCount() != 1 || heap.staticRootCount() != 1)
    throw std::runtime_error("startup storage lifetime differs");
  bool rejected = false;
  try { hxhx_program_run(heap); } catch (const std::logic_error&) { rejected = true; }
  if (!rejected || state->field_0.read().asInteger() != 123465)
    throw std::runtime_error("second startup changed existing program state");
  hxhx::managed::Heap independent(0);
  hxhx_program_run(independent);
  if (independent.requireStatic<hxhx_statics_program>()->field_0.read().asInteger() != 123465)
    throw std::runtime_error("startup leaked across heaps");
}
