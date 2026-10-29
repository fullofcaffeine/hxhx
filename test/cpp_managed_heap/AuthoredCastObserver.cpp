#define main generated_process_entry
#include "Main.cpp"
#undef main
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;

// Observe all source results and the single effect after ordinary program execution.
static void observe(Heap& heap) {
  hxhx_program_run(heap);
  heap.collect();
  const auto state = heap.requireStatic<hxhx_statics_program>();
  if (state->field_0.read().asInteger() != 7 ||
      state->field_1.read().asInteger() != 7 ||
      state->field_2.read().asInteger() != 1 ||
      state->field_3.read().asInteger() != 7 ||
      state->field_4.read().asInteger() != 11 ||
      state->field_5.read().asInteger() != 11 ||
      state->field_6.read().asInteger() != 13 ||
      state->field_7.read().asInteger() != 13 ||
      state->field_8.read().asInteger() != 7 ||
      state->field_9.read().asInteger() != 14)
    throw std::runtime_error("authored cast changed a stored value or evaluation count");
}

int main() try {
  Heap collecting(0);
  Heap ordinary(1024 * 1024);
  observe(collecting);
  observe(ordinary);
  std::cout << "CPP_MANAGED_AUTHORED_CAST:PASS\n";
} catch (const std::exception& failure) {
  std::cerr << failure.what() << '\n';
  return 1;
}
