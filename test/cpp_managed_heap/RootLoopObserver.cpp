#include "Generated.hpp"
#include <iostream>
#include <stdexcept>

// Collection at every allocation exposes iteration cells retained by escaped closures.
int main() {
  hxhx::managed::Heap heap(0);
  std::cout << generated_nulls(heap) << '\n';
  std::cout << generated_indexed(heap) << '\n';
  std::cout << generated_nested(heap) << '\n';
  std::cout << generated_captures(heap) << '\n';
  std::cout << generated_range(heap) << '\n';
  std::cout << generated_repeated(heap) << '\n';
  std::cout << generated_early(heap) << '\n';
  std::cout << generated_rangeCaptures(heap) << '\n';
  heap.collect();
  if (heap.liveCount() != 0) throw std::runtime_error("loop storage escaped its lifetime");
}
