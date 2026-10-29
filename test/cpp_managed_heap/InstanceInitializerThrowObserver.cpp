// Observe the generated runner directly; no generated artifact is rewritten.
#define main generated_process_entry
#include "Main.cpp"
#undef main
#include <iostream>
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  bool caught = false;
  try {
    hxhx_program_run(heap);
  } catch (const hxhx::managed::ThrownValue& error) {
    heap.collect();
    if (error.value().kind() != hxhx::managed::ValueKind::String ||
        error.value().asString() != "initializer")
      throw std::runtime_error("initializer failure did not precede constructor execution");
    if (heap.rootCount() != 1 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
      throw std::runtime_error("failed construction retained receiver or child storage");
    caught = true;
    std::cout << error.value().asString() << '\n';
  }
  if (!caught) throw std::runtime_error("initializer failure was omitted");
  heap.collect();
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1)
    throw std::runtime_error("initializer failure retained temporary roots after catch");
}
