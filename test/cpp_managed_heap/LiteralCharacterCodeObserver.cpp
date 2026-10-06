#define main generated_process_entry
#include "Main.cpp"
#undef main
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;

// Inspect actual static storage after the generated program has initialized it.
static void observe(Heap& heap) {
  hxhx_program_run(heap);
  heap.collect();
  const auto state = heap.requireStatic<hxhx_statics_program>();
  if (state->field_0.read().asInteger() != 65 ||
      state->field_1.read().asInteger() != 128512 ||
      state->field_2.read().asInteger() != 233 ||
      state->field_3.read().asInteger() != 1114111 ||
      state->field_4.read().asInteger() != 10 ||
      state->field_5.read().asInteger() != 0 ||
      state->field_6.read().asInteger() != 65 ||
      state->field_7.read().asInteger() != 32)
    throw std::runtime_error("literal character code lost its integer value");
}

int main() try {
  Heap collecting(0);
  Heap ordinary(1024 * 1024);
  observe(collecting);
  observe(ordinary);
  std::cout << "CPP_LITERAL_CHARACTER_CODE:PASS\n";
} catch (const std::exception& failure) {
  std::cerr << failure.what() << '\n';
  return 1;
}
