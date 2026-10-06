#include "Generated.hpp"
#include <iostream>
#include <stdexcept>
using namespace hxhx::managed;
int main() {
  Heap heap(0);
  Root<Value> result(heap);
  generated_combine(heap, result, Value(), Value::string("x"));
  if (result.get().asString() != "nullx") throw std::runtime_error("left null changed");
  generated_combine(heap, result, Value::string("x"), Value());
  if (result.get().asString() != "xnull") throw std::runtime_error("right null changed");
  // Upstream Haxe 4.3.7 with hxcpp 4.3.2 prints nullnull here; eval and Neko throw.
  generated_combine(heap, result, Value(), Value());
  heap.collect();
  if (result.get().asString() != "nullnull") throw std::runtime_error("native C++ null concatenation changed");
  std::cout << "MANAGED_STRING_NULL_NATIVE:PASS\n";
}
