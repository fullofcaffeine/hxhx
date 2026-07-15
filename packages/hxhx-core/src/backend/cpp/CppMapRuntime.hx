package backend.cpp;

/**
	Target-owned generic Map runtime emitted by the C++ backend.

	The carrier keeps Haxe Map operations coherent in generated C++ while its
	runtime type probe exposes the key-based IntMap/StringMap/ObjectMap/
	EnumValueMap specialization selected by upstream Haxe.
**/
class CppMapRuntime {
	/**
		Emit the generic carrier, nullable lookup contract, and key comparator.

		Object keys keep shared-pointer identity ordering. Enum carriers instead use
		their stable enum name/index/parameter metadata so separately materialized
		values representing the same Haxe enum constructor address the same entry.
	**/
	public static function lines(typeParams:Array<String>):Array<String> {
		final params = typeParams == null || typeParams.length < 2 ? ["K", "V"] : typeParams;
		final keyType = params[0];
		final valueType = params[1];
		return [
			"template<typename K>",
			"struct __hxhx_map_key_less {",
			"  bool operator()(const K& left, const K& right) const {",
			"    if constexpr (__hxhx_is_shared_ptr<K>::value) {",
			"      using __hxhx_map_key_type = typename K::element_type;",
			"      if constexpr (__hxhx_has_enum_metadata<__hxhx_map_key_type>::value) {",
			"        if (left == nullptr || right == nullptr) return left == nullptr && right != nullptr;",
			"        if (left->__hxhx_enum_name != right->__hxhx_enum_name) return left->__hxhx_enum_name < right->__hxhx_enum_name;",
			"        if (left->__hxhx_enum_index != right->__hxhx_enum_index) return left->__hxhx_enum_index < right->__hxhx_enum_index;",
			"        return left->__hxhx_enum_params < right->__hxhx_enum_params;",
			"      } else {",
			"        return std::less<K>{}(left, right);",
			"      }",
			"    } else {",
			"      return std::less<K>{}(left, right);",
			"    }",
			"  }",
			"};",
			"",
			"template<typename " + params.join(", typename ") + ">",
			"struct Map {",
			"  std::map<" + keyType + ", " + valueType + ", __hxhx_map_key_less<" + keyType + ">> values;",
			"  Map() {}",
			"  void set(" + keyType + " key, " + valueType + " value) {",
			"    values[key] = value;",
			"  }",
			"  std::optional<" + valueType + "> get(" + keyType + " key) {",
			"    auto found = values.find(key);",
			"    return found == values.end() ? std::nullopt : std::optional<" + valueType + ">(found->second);",
			"  }",
			"  " + valueType + "& operator[](" + keyType + " key) {",
			"    return values[key];",
			"  }",
			"  const " + valueType + "& operator[](" + keyType + " key) const {",
			"    return values.at(key);",
			"  }",
			"  bool exists(" + keyType + " key) {",
			"    return values.find(key) != values.end();",
			"  }",
			"  bool remove(" + keyType + " key) {",
			"    return values.erase(key) > 0;",
			"  }",
			"  std::shared_ptr<__hxhx_iterator<" + keyType + ">> keys() {",
			"    std::vector<" + keyType + "> out;",
			"    for (const auto& entry : values) out.push_back(entry.first);",
			"    return __hxhx_vector_iterator_of(out);",
			"  }",
			"  std::string toString() {",
			"    std::vector<std::pair<" + keyType + ", " + valueType + ">> out;",
			"    for (const auto& entry : values) out.push_back(std::make_pair(entry.first, entry.second));",
			"    return __hxhx_map_literal_to_string(out);",
			"  }",
			"};",
			"",
			"template<typename K, typename V>",
			"static bool __hxhx_is_type(const std::shared_ptr<Map<K, V>>&, const std::string& type) {",
			"  if (type == \"Map\" || type == \"haxe.ds.Map\" || type == \"Dynamic\" || type == \"Any\") return true;",
			"  if constexpr (std::is_same<K, int>::value) {",
			"    return type == \"IntMap\" || type == \"haxe.ds.IntMap\";",
			"  } else if constexpr (std::is_same<K, std::string>::value) {",
			"    return type == \"StringMap\" || type == \"haxe.ds.StringMap\";",
			"  } else if constexpr (__hxhx_is_shared_ptr<K>::value) {",
			"    using __hxhx_map_key_type = typename K::element_type;",
			"    if constexpr (__hxhx_has_enum_metadata<__hxhx_map_key_type>::value) {",
			"      return type == \"EnumValueMap\" || type == \"haxe.ds.EnumValueMap\";",
			"    } else {",
			"      return type == \"ObjectMap\" || type == \"haxe.ds.ObjectMap\";",
			"    }",
			"  } else {",
			"    return type == \"ObjectMap\" || type == \"haxe.ds.ObjectMap\";",
			"  }",
			"}",
			"",
			"template<typename " + params.join(", typename ") + ">",
			"std::shared_ptr<Map<" + params.join(", ") + ">> __hxhx_make_shared_Map() {",
			"  return std::make_shared<Map<" + params.join(", ") + ">>();",
			"}"
		];
	}
}
