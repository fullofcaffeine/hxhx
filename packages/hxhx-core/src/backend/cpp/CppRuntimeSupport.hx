package backend.cpp;

/**
	Small target-owned C++ runtime support fragments used by `CppTargetCore`.

	Why
	- C++ Full1 burn-down needs a few runtime/library surfaces while the backend is
	  still source-only.
	- Keeping these fragments here avoids turning the main emitter into a dumping
	  ground for target runtime code.

	What/How
	- Each method returns one cohesive support block.
	- `CppTargetCore` decides where each block belongs in the generated file so
	  declaration order remains explicit at the call site.
**/
class CppRuntimeSupport {
	static function quoteCppString(value:String):String {
		if (value == null)
			return "\"\"";
		final out = new StringBuf();
		out.add("\"");
		for (i in 0...value.length) {
			final code = StringTools.fastCodeAt(value, i);
			switch (code) {
				case 34:
					out.add("\\\"");
				case 92:
					out.add("\\\\");
				case 10:
					out.add("\\n");
				case 13:
					out.add("\\r");
				case 9:
					out.add("\\t");
				case _:
					if (code < 32 || code == 127) {
						out.add("\\");
						final hundreds = Std.int(code / 64);
						final tens = Std.int((code % 64) / 8);
						final ones = code % 8;
						out.add(Std.string(hundreds));
						out.add(Std.string(tens));
						out.add(Std.string(ones));
					} else {
						out.addChar(code);
					}
			}
		}
		out.add("\"");
		return out.toString();
	}

	static function byteVectorLiteral(data:haxe.io.Bytes):String {
		if (data == null || data.length == 0)
			return "std::vector<int>{}";
		final values = new Array<String>();
		for (i in 0...data.length)
			values.push(Std.string(data.get(i)));
		return "std::vector<int>{" + values.join(", ") + "}";
	}

	public static function borrowedSharedPtrLines():Array<String> {
		return [
			"template<typename T>",
			"static std::shared_ptr<T> __hxhx_borrowed_shared(T* value) {",
			"  return std::shared_ptr<T>(value, [](T*) {});",
			"}"
		];
	}

	public static function resourceLines(resources:Array<backend.BackendResource>):Array<String> {
		final entries = new Array<String>();
		if (resources != null) {
			for (resource in resources) {
				if (resource == null)
					continue;
				entries.push("    {" + quoteCppString(resource.name) + ", " + byteVectorLiteral(resource.data) + "}");
			}
		}
		final lines = [
			"struct __hxhx_resource_entry {",
			"  std::string name;",
			"  std::vector<int> data;",
			"};",
			"",
			"static const std::vector<__hxhx_resource_entry>& __hxhx_resources() {",
			"  static const std::vector<__hxhx_resource_entry> entries = {"
		];
		for (i in 0...entries.length)
			lines.push(entries[i] + (i == entries.length - 1 ? "" : ","));
		lines.push("  };");
		lines.push("  return entries;");
		lines.push("}");
		lines.push("");
		lines.push("static std::vector<std::string> __hxhx_resource_names() {");
		lines.push("  std::vector<std::string> out;");
		lines.push("  for (const auto& entry : __hxhx_resources()) out.push_back(entry.name);");
		lines.push("  return out;");
		lines.push("}");
		lines.push("");
		lines.push("static std::optional<std::string> __hxhx_resource_string(const std::string& name) {");
		lines.push("  for (const auto& entry : __hxhx_resources()) {");
		lines.push("    if (entry.name == name) {");
		lines.push("      std::string out;");
		lines.push("      out.reserve(entry.data.size());");
		lines.push("      for (int b : entry.data) out.push_back(static_cast<char>(b & 0xFF));");
		lines.push("      return out;");
		lines.push("    }");
		lines.push("  }");
		lines.push("  return std::nullopt;");
		lines.push("}");
		lines.push("");
		lines.push("static std::optional<std::vector<int>> __hxhx_resource_bytes(const std::string& name) {");
		lines.push("  for (const auto& entry : __hxhx_resources()) if (entry.name == name) return entry.data;");
		lines.push("  return std::nullopt;");
		lines.push("}");
		return lines;
	}

	public static function sha1Lines():Array<String> {
		return [
			"static std::uint32_t __hxhx_sha1_rotate_left(std::uint32_t value, std::uint32_t shift) {",
			"  return (value << shift) | (value >> (32 - shift));",
			"}",
			"",
			"static std::vector<int> __hxhx_sha1_digest_bytes(const std::vector<int>& input) {",
			"  std::vector<unsigned char> message;",
			"  message.reserve(input.size() + 72);",
			"  for (int value : input) message.push_back(static_cast<unsigned char>(value & 0xFF));",
			"  const std::uint64_t bitLength = static_cast<std::uint64_t>(message.size()) * 8ULL;",
			"  message.push_back(0x80);",
			"  while ((message.size() % 64) != 56) message.push_back(0);",
			"  for (int i = 7; i >= 0; --i) message.push_back(static_cast<unsigned char>((bitLength >> (8 * i)) & 0xFF));",
			"  std::uint32_t h0 = 0x67452301U;",
			"  std::uint32_t h1 = 0xefcdab89U;",
			"  std::uint32_t h2 = 0x98badcfeU;",
			"  std::uint32_t h3 = 0x10325476U;",
			"  std::uint32_t h4 = 0xc3d2e1f0U;",
			"  for (std::size_t offset = 0; offset < message.size(); offset += 64) {",
			"    std::uint32_t words[80];",
			"    for (int i = 0; i < 16; ++i) {",
			"      const std::size_t p = offset + static_cast<std::size_t>(i * 4);",
			"      words[i] = (static_cast<std::uint32_t>(message[p]) << 24)",
			"        | (static_cast<std::uint32_t>(message[p + 1]) << 16)",
			"        | (static_cast<std::uint32_t>(message[p + 2]) << 8)",
			"        | static_cast<std::uint32_t>(message[p + 3]);",
			"    }",
			"    for (int i = 16; i < 80; ++i) words[i] = __hxhx_sha1_rotate_left(words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16], 1);",
			"    std::uint32_t a = h0;",
			"    std::uint32_t b = h1;",
			"    std::uint32_t c = h2;",
			"    std::uint32_t d = h3;",
			"    std::uint32_t e = h4;",
			"    for (int i = 0; i < 80; ++i) {",
			"      std::uint32_t f = 0;",
			"      std::uint32_t k = 0;",
			"      if (i < 20) {",
			"        f = (b & c) | ((~b) & d);",
			"        k = 0x5a827999U;",
			"      } else if (i < 40) {",
			"        f = b ^ c ^ d;",
			"        k = 0x6ed9eba1U;",
			"      } else if (i < 60) {",
			"        f = (b & c) | (b & d) | (c & d);",
			"        k = 0x8f1bbcdcU;",
			"      } else {",
			"        f = b ^ c ^ d;",
			"        k = 0xca62c1d6U;",
			"      }",
			"      const std::uint32_t temp = __hxhx_sha1_rotate_left(a, 5) + f + e + k + words[i];",
			"      e = d;",
			"      d = c;",
			"      c = __hxhx_sha1_rotate_left(b, 30);",
			"      b = a;",
			"      a = temp;",
			"    }",
			"    h0 += a;",
			"    h1 += b;",
			"    h2 += c;",
			"    h3 += d;",
			"    h4 += e;",
			"  }",
			"  std::vector<int> out;",
			"  out.reserve(20);",
			"  const std::uint32_t digest[5] = {h0, h1, h2, h3, h4};",
			"  for (std::uint32_t word : digest) {",
			"    out.push_back(static_cast<int>((word >> 24) & 0xFF));",
			"    out.push_back(static_cast<int>((word >> 16) & 0xFF));",
			"    out.push_back(static_cast<int>((word >> 8) & 0xFF));",
			"    out.push_back(static_cast<int>(word & 0xFF));",
			"  }",
			"  return out;",
			"}",
			"",
			"static std::vector<int> __hxhx_sha1_digest_string(const std::string& source) {",
			"  std::vector<int> bytes;",
			"  bytes.reserve(source.size());",
			"  for (unsigned char c : source) bytes.push_back(static_cast<int>(c));",
			"  return __hxhx_sha1_digest_bytes(bytes);",
			"}",
			"",
			"static std::string __hxhx_sha1_hex(const std::vector<int>& digest) {",
			"  static const char* hex = \"0123456789abcdef\";",
			"  std::string out;",
			"  out.reserve(digest.size() * 2);",
			"  for (int value : digest) {",
			"    const unsigned char byte = static_cast<unsigned char>(value & 0xFF);",
			"    out.push_back(hex[(byte >> 4) & 0x0F]);",
			"    out.push_back(hex[byte & 0x0F]);",
			"  }",
			"  return out;",
			"}",
			"",
			"static std::string __hxhx_sha1_hex_string(const std::string& source) {",
			"  return __hxhx_sha1_hex(__hxhx_sha1_digest_string(source));",
			"}"
		];
	}

	public static function borrowedSharedPtrExpr(typeName:String, valueExpr:String):String {
		return "__hxhx_borrowed_shared<" + typeName + ">(" + valueExpr + ")";
	}

	public static function missingDeclarationLines(cleanName:String):Null<Array<String>> {
		return switch (cleanName) {
			case "KeyValueIterator":
				["struct KeyValueIterator {", "  virtual ~KeyValueIterator() = default;", "};"];
			case "IMap":
				[
					"template<typename K, typename V>",
					"struct IMap {",
					"  virtual ~IMap() = default;",
					"  virtual std::optional<V> get(K k) = 0;",
					"  virtual void set(K k, V v) = 0;",
					"  virtual bool exists(K k) = 0;",
					"  virtual bool remove(K k) = 0;",
					"  virtual std::shared_ptr<__hxhx_iterator<K>> keys() = 0;",
					"  virtual std::shared_ptr<__hxhx_iterator<V>> iterator() = 0;",
					"  virtual std::shared_ptr<KeyValueIterator> keyValueIterator() = 0;",
					"  virtual std::shared_ptr<IMap<K, V>> copy() = 0;",
					"  virtual std::string toString() = 0;",
					"  virtual void clear() = 0;",
					"};"
				];
			case "StringMap":
				[
					"struct __hxhx_stringmap_key_iterator : public __hxhx_iterator<std::string> {",
					"  std::vector<std::string> values;",
					"  std::size_t index;",
					"  explicit __hxhx_stringmap_key_iterator(std::vector<std::string> values) : values(std::move(values)), index(0) {}",
					"  bool hasNext() override { return index < values.size(); }",
					"  std::string next() override { return values[index++]; }",
					"};",
					"template<typename V>",
					"struct StringMap {",
					"  std::map<std::string, V> __values;",
					"  V get(std::string key) {",
					"    auto it = __values.find(key);",
					"    return it == __values.end() ? V() : it->second;",
					"  }",
					"  void set(std::string key, V value) { __values[key] = value; }",
					"  std::shared_ptr<__hxhx_iterator<std::string>> keys() {",
					"    std::vector<std::string> out;",
					"    for (const auto& item : __values) out.push_back(item.first);",
					"    return std::make_shared<__hxhx_stringmap_key_iterator>(std::move(out));",
					"  }",
					"  std::string toString() { return std::string(\"[object StringMap]\"); }",
					"};"
				];
			case "Date":
				["struct Date {", "  std::string toString() { return std::string(); }", "};"];
			case _:
				null;
		}
	}

	public static function missingMethodReturnType(cleanClassName:String, cleanMethodName:String):String {
		return switch (cleanClassName) {
			case "IMap":
				switch (cleanMethodName) {
					case "get":
						"std::optional<std::string>";
					case "set" | "clear":
						"void";
					case "exists" | "remove":
						"bool";
					case "keys" | "iterator":
						"std::shared_ptr<__hxhx_iterator<std::string>>";
					case "keyValueIterator":
						"std::shared_ptr<KeyValueIterator>";
					case "copy":
						"std::shared_ptr<IMap>";
					case "toString":
						"std::string";
					case _:
						"";
				}
			case "StringMap":
				switch (cleanMethodName) {
					case "get" | "toString":
						"std::string";
					case "set":
						"void";
					case "keys":
						"std::shared_ptr<__hxhx_iterator<std::string>>";
					case _:
						"";
				}
			case _:
				"";
		}
	}

	public static function anySupportLines():Array<String> {
		return [
			"struct Any {",
			"  std::any __value;",
			"  Any() = default;",
			"  template<typename T>",
			"  Any(T value) : __value(value) {}",
			"  template<typename T>",
			"  T __promote() const {",
			"    if constexpr (std::is_same_v<T, std::any>) return __value;",
			"    else if constexpr (std::is_same_v<T, std::string>) return __hxhx_stringify(__value);",
			"    else if (__value.has_value() && __value.type() == typeid(T)) return std::any_cast<T>(__value);",
			"    else return T{};",
			"  }",
			"  std::string toString() const { return __hxhx_stringify(__value); }",
			"};"
		];
	}

	public static function fpReinterpretLines():Array<String> {
		return [
			"static double __hxhx_reinterpret_le_int32_as_float32(int value) {",
			"  std::uint32_t bits = static_cast<std::uint32_t>(value);",
			"  float out = 0;",
			"  std::memcpy(&out, &bits, sizeof(out));",
			"  return static_cast<double>(out);",
			"}",
			"",
			"static int __hxhx_reinterpret_float32_as_le_int32(double value) {",
			"  float narrowed = static_cast<float>(value);",
			"  std::uint32_t bits = 0;",
			"  std::memcpy(&bits, &narrowed, sizeof(bits));",
			"  return static_cast<int>(bits);",
			"}",
			"",
			"static double __hxhx_reinterpret_le_int32s_as_float64(int low, int high) {",
			"  std::uint64_t bits = (static_cast<std::uint64_t>(static_cast<std::uint32_t>(high)) << 32) | static_cast<std::uint32_t>(low);",
			"  double out = 0;",
			"  std::memcpy(&out, &bits, sizeof(out));",
			"  return out;",
			"}",
			"",
			"static int __hxhx_reinterpret_float64_as_le_int32_low(double value) {",
			"  std::uint64_t bits = 0;",
			"  std::memcpy(&bits, &value, sizeof(bits));",
			"  return static_cast<int>(static_cast<std::uint32_t>(bits & 0xFFFFFFFFULL));",
			"}",
			"",
			"static int __hxhx_reinterpret_float64_as_le_int32_high(double value) {",
			"  std::uint64_t bits = 0;",
			"  std::memcpy(&bits, &value, sizeof(bits));",
			"  return static_cast<int>(static_cast<std::uint32_t>((bits >> 32) & 0xFFFFFFFFULL));",
			"}"
		];
	}

	public static function dateIntrinsicLines():Array<String> {
		return [
			"static double __hxhx_utc_date(int year, int month, int day, int hour, int min, int sec) {",
			"  std::tm tm = {};",
			"  tm.tm_year = year - 1900;",
			"  tm.tm_mon = month;",
			"  tm.tm_mday = day;",
			"  tm.tm_hour = hour;",
			"  tm.tm_min = min;",
			"  tm.tm_sec = sec;",
			"#if defined(_WIN32)",
			"  return static_cast<double>(_mkgmtime(&tm));",
			"#else",
			"  return static_cast<double>(timegm(&tm));",
			"#endif",
			"}"
		];
	}

	public static function stdIntrinsicLines():Array<String> {
		return [
			"static std::optional<int> __hxhx_parse_int(const std::string& value) {",
			"  try {",
			"    std::size_t parsed = 0;",
			"    int base = (value.size() >= 2 && value[0] == '0' && (value[1] == 'x' || value[1] == 'X')) ? 16 : 10;",
			"    int out = std::stoi(value, &parsed, base);",
			"    return parsed == 0 ? std::nullopt : std::optional<int>(out);",
			"  } catch (...) {",
			"    return std::nullopt;",
			"  }",
			"}",
			"",
			"static long long __hxhx_int_literal(const std::string& raw, const std::string& suffix) {",
			"  int base = (raw.size() >= 2 && raw[0] == '0' && (raw[1] == 'x' || raw[1] == 'X')) ? 16 : 10;",
			"  if (base == 16 || suffix == \"u32\" || suffix == \"u64\") return static_cast<long long>(std::stoull(raw, nullptr, base));",
			"  return static_cast<long long>(std::stoll(raw, nullptr, base));",
			"}",
			"",
			"static int __hxhx_int64_to_int(long long value) {",
			"  if (value < std::numeric_limits<int>::min() || value > std::numeric_limits<int>::max()) throw std::runtime_error(\"Overflow\");",
			"  return static_cast<int>(value);",
			"}"
		];
	}

	public static function baseCodeLines():Array<String> {
		return [
			"static int __hxhx_basecode_nbits(const std::vector<int>& alphabet) {",
			"  int len = static_cast<int>(alphabet.size());",
			"  int nbits = 1;",
			"  while (len > (1 << nbits)) ++nbits;",
			"  if (nbits > 8 || len != (1 << nbits)) throw std::runtime_error(\"BaseCode : base length must be a power of two.\");",
			"  return nbits;",
			"}",
			"",
			"static std::vector<int> __hxhx_basecode_table(const std::vector<int>& alphabet) {",
			"  std::vector<int> table(256, -1);",
			"  for (std::size_t i = 0; i < alphabet.size(); ++i) table[static_cast<unsigned char>(alphabet[i] & 0xFF)] = static_cast<int>(i);",
			"  return table;",
			"}",
			"",
			"static std::vector<int> __hxhx_basecode_encode_bytes(const std::vector<int>& bytes, const std::vector<int>& alphabet, int nbits) {",
			"  int buf = 0;",
			"  int curbits = 0;",
			"  const int mask = (1 << nbits) - 1;",
			"  const int size = static_cast<int>((bytes.size() * 8) / nbits);",
			"  std::vector<int> out(static_cast<std::size_t>(size + (((bytes.size() * 8) % nbits == 0) ? 0 : 1)));",
			"  int pin = 0;",
			"  int pout = 0;",
			"  while (pout < size) {",
			"    while (curbits < nbits) {",
			"      curbits += 8;",
			"      buf <<= 8;",
			"      buf |= bytes[static_cast<std::size_t>(pin++)] & 0xFF;",
			"    }",
			"    curbits -= nbits;",
			"    out[static_cast<std::size_t>(pout++)] = alphabet[static_cast<std::size_t>((buf >> curbits) & mask)] & 0xFF;",
			"  }",
			"  if (curbits > 0) out[static_cast<std::size_t>(pout++)] = alphabet[static_cast<std::size_t>((buf << (nbits - curbits)) & mask)] & 0xFF;",
			"  return out;",
			"}",
			"",
			"static std::vector<int> __hxhx_basecode_decode_bytes(const std::vector<int>& bytes, const std::vector<int>& alphabet, int nbits) {",
			"  auto table = __hxhx_basecode_table(alphabet);",
			"  const int size = static_cast<int>((bytes.size() * nbits) >> 3);",
			"  std::vector<int> out(static_cast<std::size_t>(size));",
			"  int buf = 0;",
			"  int curbits = 0;",
			"  int pin = 0;",
			"  int pout = 0;",
			"  while (pout < size) {",
			"    while (curbits < 8) {",
			"      curbits += nbits;",
			"      buf <<= nbits;",
			"      int value = table[static_cast<unsigned char>(bytes[static_cast<std::size_t>(pin++)] & 0xFF)];",
			"      if (value == -1) throw std::runtime_error(\"BaseCode : invalid encoded char\");",
			"      buf |= value;",
			"    }",
			"    curbits -= 8;",
			"    out[static_cast<std::size_t>(pout++)] = (buf >> curbits) & 0xFF;",
			"  }",
			"  return out;",
			"}",
			"",
			"static std::string __hxhx_basecode_string_from_bytes(const std::vector<int>& bytes) {",
			"  std::string out;",
			"  __hxhx_string_of_bytes(bytes, out, 0, static_cast<int>(bytes.size()));",
			"  return out;",
			"}",
			"",
			"static std::string __hxhx_basecode_encode_string(const std::string& source, const std::vector<int>& alphabet, int nbits) {",
			"  std::vector<int> bytes;",
			"  __hxhx_bytes_of_string(bytes, source);",
			"  return __hxhx_basecode_string_from_bytes(__hxhx_basecode_encode_bytes(bytes, alphabet, nbits));",
			"}",
			"",
			"static std::string __hxhx_basecode_decode_string(const std::string& source, const std::vector<int>& alphabet, int nbits) {",
			"  std::vector<int> bytes;",
			"  __hxhx_bytes_of_string(bytes, source);",
			"  return __hxhx_basecode_string_from_bytes(__hxhx_basecode_decode_bytes(bytes, alphabet, nbits));",
			"}"
		];
	}

	public static function vectorSupportLines():Array<String> {
		return [
			"template<typename T>",
			"static T __hxhx_vector_get(const std::vector<T>& values, int index) {",
			"  if (index < 0 || static_cast<std::size_t>(index) >= values.size()) return T{};",
			"  return values[static_cast<std::size_t>(index)];",
			"}",
			"",
			"template<typename T>",
			"static T __hxhx_vector_pop(std::vector<T>& values) {",
			"  if (values.empty()) return T{};",
			"  T value = values.back();",
			"  values.pop_back();",
			"  return value;",
			"}",
			"",
			"template<typename T, typename U>",
			"static bool __hxhx_vector_value_eq(const T& value, const U& expected) {",
			"  return value == expected;",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_vector_value_eq(const std::optional<T>& value, const T& expected) {",
			"  return value.has_value() && value.value() == expected;",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_vector_value_eq(const std::optional<T>& value, std::nullptr_t) {",
			"  return !value.has_value();",
			"}",
			"",
			"template<typename T, typename U>",
			"static bool __hxhx_vector_remove(std::vector<T>& values, const U& needle) {",
			"  for (auto it = values.begin(); it != values.end(); ++it) {",
			"    if (__hxhx_vector_value_eq(*it, needle)) {",
			"      values.erase(it);",
			"      return true;",
			"    }",
			"  }",
			"  return false;",
			"}",
			"",
			"template<typename T>",
			"static std::vector<T> __hxhx_vector_splice(std::vector<T>& values, int pos, int len) {",
			"  int size = static_cast<int>(values.size());",
			"  int start = pos < 0 ? size + pos : pos;",
			"  if (start < 0) start = 0;",
			"  if (start > size) start = size;",
			"  int count = len < 0 ? 0 : len;",
			"  int end = start + count;",
			"  if (end > size) end = size;",
			"  auto first = values.begin() + start;",
			"  auto last = values.begin() + end;",
			"  std::vector<T> removed(first, last);",
			"  values.erase(first, last);",
			"  return removed;",
			"}"
		];
	}

	public static function sysEventLoopLines():Array<String> {
		return [
			"template<typename T>",
			"static T __hxhx_shift(std::vector<T>& values) {",
			"  T value = values.front();",
			"  values.erase(values.begin());",
			"  return value;",
			"}",
			"",
			"// hxhx-cpp-unsupported: Timer.delay has no Cpp event-loop scheduler yet; see docs/00-project/CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md.",
			"struct Timer {",
			"  bool stopped = false;",
			"  static double stamp() {",
			"    using clock = std::chrono::steady_clock;",
			"    static const auto start = clock::now();",
			"    return std::chrono::duration<double>(clock::now() - start).count();",
			"  }",
			"  static std::shared_ptr<Timer> delay(std::function<void()> f, double ms) {",
			"    (void)f;",
			"    (void)ms;",
			"    throw std::runtime_error(\"hxhx cpp Timer.delay scheduling unsupported\");",
			"  }",
			"  void stop() { stopped = true; }",
			"};",
			"",
			"struct __hxhx_http_bytes {",
			"  std::vector<int> values;",
			"  std::size_t size() const { return values.size(); }",
			"  int get(int index) const { return index < 0 || static_cast<std::size_t>(index) >= values.size() ? 0 : values[static_cast<std::size_t>(index)]; }",
			"};",
			"",
			"// hxhx-cpp-bounded-bringup: Http preserves callback/request shape and reports unsupported transport through onError; see docs/00-project/CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md.",
			"struct Http {",
			"  std::string url;",
			"  bool hasPostData = false;",
			"  bool hasPostBytes = false;",
			"  std::function<void(std::string)> onData = nullptr;",
			"  std::function<void(std::string)> onError = nullptr;",
			"  std::function<void(__hxhx_http_bytes)> onBytes = nullptr;",
			"  explicit Http(std::string url = std::string()) : url(url) {}",
			"  void setPostData(std::string value) { (void)value; hasPostData = true; hasPostBytes = false; }",
			"  template<typename T>",
			"  void setPostBytes(T value) { (void)value; hasPostBytes = true; hasPostData = false; }",
			"  void request(std::optional<bool> post = std::nullopt) {",
			"    (void)post;",
			"    std::string message = std::string(\"hxhx cpp Http transport unsupported\");",
			"    if (!url.empty()) message += std::string(\": \") + url;",
			"    if (onError) {",
			"      onError(message);",
			"      return;",
			"    }",
			"    throw std::runtime_error(message);",
			"  }",
			"};",
			"",
			"// hxhx-cpp-bounded-bringup: Lock supports release counts/timeouts; Mutex supports recursive owner locking. Cross-thread Haxe scheduling remains classified in docs/00-project/CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md.",
			"struct Lock {",
			"  std::mutex mutex;",
			"  std::condition_variable condition;",
			"  int releases = 0;",
			"  void acquire() {}",
			"  bool wait(std::optional<double> timeout = std::nullopt) {",
			"    std::unique_lock<std::mutex> lock(mutex);",
			"    auto ready = [&]() { return releases > 0; };",
			"    bool released = true;",
			"    if (!timeout.has_value() || timeout.value() < 0) {",
			"      condition.wait(lock, ready);",
			"    } else {",
			"      released = condition.wait_for(lock, std::chrono::duration<double>(timeout.value()), ready);",
			"    }",
			"    if (!released) return false;",
			"    releases--;",
			"    return true;",
			"  }",
			"  void release() {",
			"    {",
			"      std::lock_guard<std::mutex> lock(mutex);",
			"      releases++;",
			"    }",
			"    condition.notify_one();",
			"  }",
			"};",
			"",
			"struct Mutex {",
			"  std::recursive_mutex mutex;",
			"  void acquire() { mutex.lock(); }",
			"  bool tryAcquire() { return mutex.try_lock(); }",
			"  void release() { mutex.unlock(); }",
			"};",
			"",
			"struct MainLoop;",
			"",
			"// hxhx-cpp-smoke-only: MainLoop/MainEvent use a single synchronous pending list, not full event-loop scheduling.",
			"struct MainEvent {",
			"  std::function<void()> f;",
			"  std::shared_ptr<MainEvent> prev = nullptr;",
			"  std::shared_ptr<MainEvent> next = nullptr;",
			"  double nextRun = -std::numeric_limits<double>::infinity();",
			"  int priority = 0;",
			"  bool isMain = false;",
			"  MainEvent(std::function<void()> f = nullptr, std::optional<int> priority = std::nullopt) : f(f), priority(priority.value_or(0)) {}",
			"  void delay(std::optional<double> t = std::nullopt);",
			"  void stop();",
			"  void wakeup() {}",
			"};",
			"",
			"struct MainLoop {",
			"  inline static std::shared_ptr<MainEvent> pending = nullptr;",
			"  static std::shared_ptr<MainEvent> add(std::function<void()> f, std::optional<int> priority = std::nullopt) {",
			"    auto event = std::make_shared<MainEvent>(f, priority);",
			"    event->next = pending;",
			"    if (pending != nullptr) pending->prev = event;",
			"    pending = event;",
			"    return event;",
			"  }",
			"  static bool hasEvents() { return pending != nullptr; }",
			"  static void sortEvents() {}",
			"  static double tick() {",
			"    sortEvents();",
			"    auto event = pending;",
			"    if (event == nullptr) return -std::numeric_limits<double>::infinity();",
			"    pending = event->next;",
			"    if (pending != nullptr) pending->prev = nullptr;",
			"    event->next = nullptr;",
			"    if (event->f) event->f();",
			"    return pending == nullptr ? -std::numeric_limits<double>::infinity() : pending->nextRun;",
			"  }",
			"};",
			"",
			"inline void MainEvent::delay(std::optional<double> t) {",
			"  nextRun = !t.has_value() ? -std::numeric_limits<double>::infinity() : Timer::stamp() + t.value();",
			"}",
			"",
			"inline void MainEvent::stop() {",
			"  if (prev != nullptr) prev->next = next;",
			"  if (next != nullptr) next->prev = prev;",
			"  if (MainLoop::pending.get() == this) MainLoop::pending = next;",
			"  prev = nullptr;",
			"  next = nullptr;",
			"}",
			"",
			"// hxhx-cpp-smoke-only: EntryPoint drains queued callbacks synchronously; thread handling is not parity support.",
			"struct EntryPoint {",
			"  inline static std::shared_ptr<Lock> sleepLock = std::make_shared<Lock>();",
			"  inline static std::shared_ptr<Mutex> mutex = std::make_shared<Mutex>();",
			"  inline static int threadCount = 0;",
			"  inline static std::vector<std::function<void()>> pending = {};",
			"  static void wakeup() { sleepLock->release(); }",
			"  static void runInMainThread(std::function<void()> f) {",
			"    mutex->acquire();",
			"    pending.push_back(f);",
			"    mutex->release();",
			"    wakeup();",
			"  }",
			"  static void addThread(std::function<void()> f) {",
			"    mutex->acquire();",
			"    threadCount++;",
			"    mutex->release();",
			"    if (f) f();",
			"    mutex->acquire();",
			"    threadCount--;",
			"    mutex->release();",
			"  }",
			"  static double processEvents() {",
			"    mutex->acquire();",
			"    while (!pending.empty()) {",
			"      auto f = __hxhx_shift(pending);",
			"      mutex->release();",
			"      if (f) f();",
			"      mutex->acquire();",
			"    }",
			"    mutex->release();",
			"    double time = MainLoop::tick();",
			"    return (!MainLoop::hasEvents() && threadCount == 0) ? -std::numeric_limits<double>::infinity() : time;",
			"  }",
			"};"
		];
	}

	public static function rttiMetaLines():Array<String> {
		return [
			"// hxhx-cpp-bounded-bringup: erased metadata support is smoke-only; see docs/00-project/CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md.",
			"template<typename TResult, typename T>",
			"static TResult __hxhx_meta_get_as(const T&) {",
			"  return TResult{};",
			"}",
			"",
			"template<typename TResult, typename T>",
			"static TResult __hxhx_meta_section_as(const T&, const std::string&) {",
			"  return TResult{};",
			"}",
			"",
			"static std::any __hxhx_reflect_get_property_any(const std::any&, const std::string&) {",
			"  return std::any();",
			"}",
			"",
			"static bool __hxhx_reflect_has_field_any(const std::any&, const std::string&) {",
			"  return false;",
			"}",
			"",
			"template<typename TObject>",
			"static std::any __hxhx_reflect_field(const TObject&, const std::string&) {",
			"  // hxhx-cpp-bounded-bringup: erased Reflect.field returns an empty carrier until oracle-backed support or diagnostics exist.",
			"  return std::any();",
			"}",
			"",
			"template<typename TObject, typename TValue>",
			"static void __hxhx_reflect_set_field(TObject&, const std::string&, const TValue&) {",
			"  // hxhx-cpp-bounded-bringup: compile-safe Serializer object shape only; this does not mutate erased objects.",
			"}",
			"",
			"template<typename TObject, typename TFunc, typename TArgs>",
			"static std::any __hxhx_reflect_call_method(const TObject&, const TFunc&, const TArgs&) {",
			"  // hxhx-cpp-bounded-bringup: erased Reflect.callMethod is not runtime parity support.",
			"  return std::any();",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_reflect_is_function(const T&) {",
			"  return false;",
			"}",
			"",
			"template<typename R, typename... Args>",
			"static bool __hxhx_reflect_is_function(const std::function<R(Args...)>&) {",
			"  return true;",
			"}",
			"",
			"struct __hxhx_method_identity {",
			"  const void* target;",
			"  std::string method;",
			"  explicit __hxhx_method_identity(const void* target = nullptr, std::string method = std::string()) : target(target), method(method) {}",
			"};",
			"",
			"static bool __hxhx_reflect_compare_methods(const __hxhx_method_identity& left, const __hxhx_method_identity& right) {",
			"  return !left.method.empty() && left.target == right.target && left.method == right.method;",
			"}",
			"",
			"template<typename B>",
			"static bool __hxhx_reflect_compare_methods(const __hxhx_method_identity&, const B&) {",
			"  return false;",
			"}",
			"",
			"template<typename A>",
			"static bool __hxhx_reflect_compare_methods(const A&, const __hxhx_method_identity&) {",
			"  return false;",
			"}",
			"",
			"template<typename A, typename B>",
			"static bool __hxhx_reflect_compare_methods(const A&, const B&) {",
			"  return false;",
			"}"
		];
	}

	public static function enumValueTypeLines():Array<String> {
		return [
			"struct EnumValue {",
			"  std::string tag;",
			"  int index;",
			"  std::vector<std::string> parameters;",
			"  explicit EnumValue(std::string tag = std::string(), int index = 0, std::vector<std::string> parameters = {}) : tag(tag), index(index), parameters(parameters) {}",
			"  std::string getName() const { return tag; }",
			"  int getIndex() const { return index; }",
			"  std::vector<std::string> getParameters() const { return parameters; }",
			"};"
		];
	}

	public static function anyIsTypeLines():Array<String> {
		return [
			"static bool __hxhx_is_type(const std::any& value, const std::string& type) {",
			"  if (type == \"Dynamic\" || type == \"Any\") return true;",
			"  if (!value.has_value()) return type == \"Null\";",
			"  const std::type_info& valueType = value.type();",
			"  if (type == \"Array\") return valueType == typeid(std::vector<std::string>) || valueType == typeid(std::vector<int>);",
			"  if (type == \"String\" || type == \"StdTypes.String\") return valueType == typeid(std::string) || valueType == typeid(const char*);",
			"  if (type == \"Bool\" || type == \"StdTypes.Bool\") return valueType == typeid(bool);",
			"  if (type == \"Int\" || type == \"StdTypes.Int\") return valueType == typeid(int);",
			"  if (type == \"Float\" || type == \"StdTypes.Float\") return valueType == typeid(double) || valueType == typeid(float);",
			"  return false;",
			"}"
		];
	}

	public static function enumValueDynamicLines():Array<String> {
		return [
			"// hxhx-cpp-bounded-bringup: erased enum/array/numeric extraction is partial; see docs/00-project/CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md.",
			"static bool __hxhx_is_enum_value(const std::shared_ptr<EnumValue>& value) {",
			"  return value != nullptr;",
			"}",
			"",
			"static bool __hxhx_is_enum_value(const std::any& value) {",
			"  return value.has_value() && value.type() == typeid(std::shared_ptr<EnumValue>) && std::any_cast<std::shared_ptr<EnumValue>>(value) != nullptr;",
			"}",
			"",
			"template<typename T>",
			"static bool __hxhx_is_enum_value(const T&) {",
			"  return false;",
			"}",
			"",
			"static std::shared_ptr<EnumValue> __hxhx_enum_value_ptr(const std::any& value) {",
			"  if (__hxhx_is_enum_value(value)) return std::any_cast<std::shared_ptr<EnumValue>>(value);",
			"  return nullptr;",
			"}",
			"",
			"static std::vector<std::string> __hxhx_string_vector_any(const std::any& value) {",
			"  if (!value.has_value()) return {};",
			"  if (value.type() == typeid(std::vector<std::string>)) return std::any_cast<std::vector<std::string>>(value);",
			"  return {};",
			"}",
			"",
			"static double __hxhx_any_double(const std::any& value) {",
			"  if (!value.has_value()) return 0.0;",
			"  if (value.type() == typeid(double)) return std::any_cast<double>(value);",
			"  if (value.type() == typeid(float)) return static_cast<double>(std::any_cast<float>(value));",
			"  if (value.type() == typeid(int)) return static_cast<double>(std::any_cast<int>(value));",
			"  if (value.type() == typeid(bool)) return std::any_cast<bool>(value) ? 1.0 : 0.0;",
			"  if (value.type() == typeid(std::string)) {",
			"    try {",
			"      return std::stod(std::any_cast<std::string>(value));",
			"    } catch (...) {",
			"      return 0.0;",
			"    }",
			"  }",
			"  return 0.0;",
			"}"
		];
	}

	public static function compareLines():Array<String> {
		return [
			"template<typename L, typename R>",
			"static int __hxhx_compare(const L& left, const R& right) {",
			"  return __hxhx_stringify(left).compare(__hxhx_stringify(right));",
			"}",
			"",
			"template<typename T>",
			"static int __hxhx_compare(const T& left, const T& right) {",
			"  if constexpr (std::is_arithmetic_v<T>) return left < right ? -1 : (left > right ? 1 : 0);",
			"  else return left < right ? -1 : (left > right ? 1 : 0);",
			"}",
			"",
			"static int __hxhx_compare(const std::shared_ptr<EnumValue>& left, const std::shared_ptr<EnumValue>& right) {",
			"  if (left == nullptr && right == nullptr) return 0;",
			"  if (left == nullptr) return -1;",
			"  if (right == nullptr) return 1;",
			"  int indexDiff = left->getIndex() - right->getIndex();",
			"  if (indexDiff != 0) return indexDiff < 0 ? -1 : 1;",
			"  return left->getName().compare(right->getName());",
			"}",
			"",
			"static int __hxhx_compare(const std::any& left, const std::any& right) {",
			"  if (__hxhx_is_enum_value(left) && __hxhx_is_enum_value(right)) return __hxhx_compare(__hxhx_enum_value_ptr(left), __hxhx_enum_value_ptr(right));",
			"  if (left.has_value() && right.has_value() && left.type() == typeid(std::string) && right.type() == typeid(std::string)) return __hxhx_compare(std::any_cast<std::string>(left), std::any_cast<std::string>(right));",
			"  if (left.has_value() && right.has_value() && left.type() == typeid(int) && right.type() == typeid(int)) return __hxhx_compare(std::any_cast<int>(left), std::any_cast<int>(right));",
			"  if (left.has_value() && right.has_value() && left.type() == typeid(double) && right.type() == typeid(double)) return __hxhx_compare(std::any_cast<double>(left), std::any_cast<double>(right));",
			"  return __hxhx_stringify(left).compare(__hxhx_stringify(right));",
			"}"
		];
	}
}
