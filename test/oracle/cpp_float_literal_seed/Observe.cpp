// Read emitted constants independently of the Haxe literal encoder.
#define main hxhx_fixture_main
#include "Main.cpp"
#undef main
#include <iomanip>
#include <iostream>

std::uint64_t bits(double value) {
  std::uint64_t result;
  std::memcpy(&result, &value, sizeof(result));
  return result;
}
void show(const char* name, const hxhx::managed::Value& value) {
  std::cout << name << ":" << std::hex << std::uppercase << std::setw(16)
            << std::setfill('0') << bits(value.asFloat()) << "\n";
}
int observe() {
  using namespace hxhx::managed;
  Heap heap(0);
  hxhx_program_run(heap);
  heap.collect();
  const auto storage = heap.requireStatic<hxhx_statics_program>();
  // Static members are sorted by declaration identity. These slots correspond
  // to the independent Main source: adjacent, largest, negative, negativeZero,
  // normal, one, precision, smallest, tenth, zero, zzLocal, zzReturned.
  show("zero", storage->field_9.read());
  show("negativeZero", storage->field_3.read());
  show("one", storage->field_5.read());
  show("tenth", storage->field_8.read());
  show("precision", storage->field_6.read());
  show("adjacent", storage->field_0.read());
  show("smallest", storage->field_7.read());
  show("normal", storage->field_4.read());
  show("largest", storage->field_1.read());
  show("negative", storage->field_2.read());
  show("local", storage->field_10.read());
  show("returned", storage->field_11.read());
  if (heap.rootCount() != 0 || heap.staticRootCount() != 1 || heap.liveCount() != 1) return 11;
  // Representation transport preserves Infinity and distinct quiet NaN payloads.
  // This does not test or authorize Math operations or NaN comparison policies.
  for (const std::uint64_t raw : {UINT64_C(0x7ff0000000000000), UINT64_C(0xfff0000000000000),
       UINT64_C(0x7ff8000000000001), UINT64_C(0x7ff8000000000002), UINT64_C(0xfff8000000000001)}) {
    if (bits(Value::floatingBits(raw).asFloat()) != raw) return 12;
  }
  return 0;
}
int main() {
  const int first = observe();
  return first == 0 ? observe() : first;
}
