#define main generated_main
#include "Main.cpp"
#undef main
#include <cmath>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <stdexcept>

static void show(const char* name, double value) {
  std::uint64_t bits;
  std::memcpy(&bits, &value, sizeof(bits));
  std::cout << name << ":" << std::hex << std::uppercase << std::setw(16)
            << std::setfill('0') << bits << "\n";
}

int main() {
  using namespace hxhx::managed;
  for (int run = 0; run < 2; ++run) {
    Heap heap(0);
    hxhx_program_run(heap);
    heap.collect();
    const auto state = heap.requireStatic<hxhx_statics_program>();
    // Authored Main fields sort as nan, negative, pi, positive, zLocal, zShadow.
    // The ordinary shadows.Math.PI field follows them and must still own storage.
    show("pi", state->field_2.read().asFloat());
    show("positive", state->field_3.read().asFloat());
    show("negative", state->field_1.read().asFloat());
    std::cout << "nan:" << (std::isnan(state->field_0.read().asFloat()) ? "true" : "false") << "\n";
    show("local", state->field_4.read().asFloat());
    show("shadow", state->field_5.read().asFloat());
    if (state->field_6.read().asFloat() != 7.0 || heap.rootCount() != 0
        || heap.staticRootCount() != 1 || heap.liveCount() != 1)
      throw std::runtime_error("Math constant reads changed shadow storage or roots");
  }
}
