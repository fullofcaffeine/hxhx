// Reuse generated source without modifying it. Each heap collects before every
// allocation, including after prime() releases its local reference to twice.
#define main hxhx_fixture_main
#include "Main.cpp"
#undef main

int main() {
  hxhx::managed::Heap first(0);
  hxhx_program_run(first);
  first.collect();
  hxhx::managed::Heap second(0);
  hxhx_program_run(second);
  second.collect();
}
