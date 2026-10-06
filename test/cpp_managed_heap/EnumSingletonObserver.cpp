// Observe the generated runner without editing its source or replacing its startup.
#define main generated_process_entry
#include "Main.cpp"
#undef main
#include <iostream>
#include <stdexcept>
#include <string>

using namespace hxhx::managed;
static void require(bool condition) {
  if (!condition) throw std::runtime_error("enum singleton startup changed its source contract");
}

static Ref<EnumPayload> observe(Heap& heap) {
  hxhx_program_run(heap);
  heap.collect();
  const auto state = heap.requireStatic<hxhx_statics_program>();
  // Canonical field order: Main's six fields, Choice.Empty/Last, Other.Empty.
  const auto empty = state->field_6.read().asManaged().as<EnumPayload>();
  const auto last = state->field_7.read().asManaged().as<EnumPayload>();
  const auto other = state->field_8.read().asManaged().as<EnumPayload>();
  require(state->field_0.read().kind() == ValueKind::Null);
  require(state->field_1.read().asManaged().as<EnumPayload>() == empty);
  require(state->field_2.read().asManaged().as<EnumPayload>() == last);
  require(state->field_3.read().asManaged().as<EnumPayload>() == last);
  require(state->field_4.read().asManaged().as<EnumPayload>() == empty);
  require(state->field_5.read().asManaged().as<EnumPayload>() == other);
  require(!(empty == last) && !(empty == other));
  require(empty->constructorIndex() == 0 && last->constructorIndex() == 1);
  require(other->constructorIndex() == 0 && empty->size() == 0);
  require(&empty->descriptor() == &last->descriptor());
  require(&empty->descriptor() != &other->descriptor());
  require(std::string(empty->descriptor().identity) == "Main.Choice");
  require(std::string(other->descriptor().identity) == "Main.Other");
  require(heap.liveCount() == 4 && heap.staticRootCount() == 1);
  bool rejected = false;
  try { hxhx_program_run(heap); } catch (const std::logic_error&) { rejected = true; }
  require(rejected && state->field_6.read().asManaged().as<EnumPayload>() == empty);
  return empty;
}

int main() try {
  Heap collecting(0);
  Heap ordinary(1024 * 1024);
  const auto first = observe(collecting);
  const auto second = observe(ordinary);
  require(!(first == second));
  std::cout << "CPP_MANAGED_ENUM_SINGLETON_STARTUP:PASS\n";
} catch (const std::exception& failure) {
  std::cerr << failure.what() << '\n';
  return 1;
}
