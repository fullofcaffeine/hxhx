// Observe the actual generated program runner without editing its artifact.
#define main generated_process_entry
#include "Main.cpp"
#undef main
#include <iostream>
#include <stdexcept>
int main() {
  hxhx::managed::Heap heap(0);
  bool caught = false;
  try { hxhx_program_run(heap); }
  catch (const hxhx::managed::ThrownValue& error) {
    heap.collect();
    if (error.value().kind() != hxhx::managed::ValueKind::String || error.value().asString() != "startup")
      throw std::runtime_error("main ran before the startup failure or the thrown value changed");
    caught = true;
    std::cout << error.value().asString() << '\n';
  }
  if (!caught) throw std::runtime_error("class startup throw was omitted");
}
