// Exercise the unmodified generated program with collection before each allocation.
#define main hxhx_generated_entry
#include "ReceiverValueMain.cpp"
#undef main

int main() {
  hxhx::managed::Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  return 0;
}
