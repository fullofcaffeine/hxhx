// Observe the original admission programs without depending on their generated text.
#define main generated_main
#include "src/Main.cpp"
#undef main
#include <stdexcept>

int main() {
  hxhx::managed::Heap heap(0);
  bool caught = false;
  try {
    hxhx_program_run(heap);
  } catch (const hxhx::managed::ThrownValue& error) {
    caught = true;
    // Throw erases the source Float into Dynamic. The native contract boxes 1.0 as Int 1.
    if (!HXHX_ADMISSION_THROW || error.value().asInteger() != 1)
      throw std::runtime_error("startup changed its thrown numeric value");
  }
  if (caught != bool(HXHX_ADMISSION_THROW))
    throw std::runtime_error("startup throw behavior changed");
#if HXHX_ADMISSION_FIELD
  // Each field fixture declares exactly one static field, whether its class is called or not.
  const auto storage = heap.requireStatic<hxhx_statics_program>();
  if (storage->field_0.read().asFloat() != 1.0)
    throw std::runtime_error("static Float initialization changed");
#endif
  heap.collect();
  if (heap.rootCount() != 0)
    throw std::runtime_error("admission execution retained temporary roots");
}
