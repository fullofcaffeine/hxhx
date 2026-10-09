#pragma once

#include <cstdio>
#include <stdexcept>
#include <string_view>

namespace hxhx::managed {

// Preserve every byte, including embedded zeroes. Haxe lowering owns formatting
// and line endings. Flush each operation before the next source effect and
// report failed writes or flushes.
inline void writeStdout(std::string_view bytes) {
  if (std::fwrite(bytes.data(), 1, bytes.size(), stdout) != bytes.size() ||
      std::fflush(stdout) != 0) {
    throw std::runtime_error("managed stdout write failed");
  }
}

} // namespace hxhx::managed
