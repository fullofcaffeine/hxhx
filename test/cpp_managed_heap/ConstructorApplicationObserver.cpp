#include "Generated.hpp"
#define main hxhx_generated_entry
#include "Applications.cpp"
#undef main
#include <iostream>
#include <stdexcept>

// Invoke the complete authored body and inspect its concrete backing allocation.
int main() {
  using namespace hxhx::managed;
  {
    Heap programHeap(0);
    hxhx_program_run(programHeap);
    programHeap.collect();
    // The program owns one empty static root for the heap's lifetime. All
    // constructor cells, captured locals, and callable environments must die.
    if (programHeap.staticRootCount() != 1 || programHeap.liveCount() != 1)
      throw std::runtime_error("generic application retained nonstatic storage");
  }
  Heap heap(0);
  {
    Root<Ref<CellPayload>> receiver(heap);
    heap.allocateInto(receiver, CellWriteMode::Replaceable);
    generated_constructor(heap, receiver.get(), Value::string("word"));
    heap.collect();
    auto array = receiver.get()->read().asManaged().as<ArrayPayload>();
    if (array->representation() != ArrayRepresentation::String || array->size() != 1)
      throw std::runtime_error("generic constructor lost concrete array storage");
    std::cout << array->read(0).asString() << '\n';
  }
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("constructor storage leaked");
}
