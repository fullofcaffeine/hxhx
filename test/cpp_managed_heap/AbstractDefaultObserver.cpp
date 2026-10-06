#define main generated_process_entry
#include "Main.cpp"
#undef main
#include <iostream>
#include <stdexcept>

using namespace hxhx::managed;
static void observe(Heap& heap) {
  hxhx_program_run(heap);
  heap.collect();
  const auto state = heap.requireStatic<hxhx_statics_program>();
  if (state->field_0.read().kind() != ValueKind::Null ||
      state->field_1.read().kind() != ValueKind::Null ||
      state->field_4.read().kind() != ValueKind::Null ||
      state->field_6.read().kind() != ValueKind::Null ||
      state->field_2.read().asBoolean() || state->field_3.read().asInteger() != 0 ||
      state->field_5.read().asInteger() != 0 ||
      heap.liveCount() != 1)
    throw std::runtime_error("abstract static default differs");
}

int main() try {
  Heap collecting(0);
  Heap ordinary(1024 * 1024);
  observe(collecting);
  observe(ordinary);
  std::cout << "CPP_MANAGED_ABSTRACT_DEFAULT:PASS\n";
} catch (const std::exception& failure) {
  std::cerr << failure.what() << '\n';
  return 1;
}
