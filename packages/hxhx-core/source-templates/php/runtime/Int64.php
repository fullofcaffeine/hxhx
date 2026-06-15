function __hxhx_int64_literal($text, $suffix) {
  $clean = str_replace("_", "", strtolower($text));
  if (strpos($clean, "0x") === 0) {
    $hex = ltrim(substr($clean, 2), "0");
    if ($hex === "") return \haxe\Int64::make(0, 0);
    if (strlen($hex) > 16) $hex = substr($hex, -16);
    $padded = str_pad($hex, 16, "0", STR_PAD_LEFT);
    return \haxe\Int64::make(hexdec(substr($padded, 0, 8)), hexdec(substr($padded, 8, 8)));
  }
  $value = intval($clean);
  return \haxe\Int64::make(($value >> 32) & 0xFFFFFFFF, $value & 0xFFFFFFFF);
}
function __hxhx_int64_parse_string($text) {
  $clean = trim(strval($text));
  if (!preg_match('/^-?[0-9]+$/', $clean)) throw new \Exception("Invalid Int64 string");
  $negative = strlen($clean) > 0 && $clean[0] === "-";
  $digits = $negative ? substr($clean, 1) : $clean;
  $digits = ltrim($digits, "0");
  if ($digits === "") return \haxe\Int64::make(0, 0);
  $limit = $negative ? "9223372036854775808" : "9223372036854775807";
  if (strlen($digits) > 19 || (strlen($digits) === 19 && strcmp($digits, $limit) > 0)) throw new \Exception("Int64 overflow");
  if ($negative && $digits === "9223372036854775808") return \haxe\Int64::make(0x80000000, 0);
  $value = intval($digits);
  if ($negative) $value = -$value;
  return \haxe\Int64::make(($value >> 32) & 0xFFFFFFFF, $value & 0xFFFFFFFF);
}
function __hxhx_int64_from_float($value) {
  $float = floatval($value);
  if (is_nan($float) || $float >= 9007199254740992.0 || $float <= -9007199254740992.0) throw new \Exception("Int64 overflow");
  $int = intval($float);
  return \haxe\Int64::make(($int >> 32) & 0xFFFFFFFF, $int & 0xFFFFFFFF);
}
function __hxhx_is_int64($value) {
  return is_object($value) && property_exists($value, "high") && property_exists($value, "low");
}
function __hxhx_int64_value($value) {
  if (__hxhx_is_int64($value)) return $value;
  if (is_string($value)) return __hxhx_int64_parse_string($value);
  return \haxe\Int64::ofInt(intval($value));
}
function __hxhx_int64_make_u($high, $low) {
  return \haxe\Int64::make($high & 0xFFFFFFFF, $low & 0xFFFFFFFF);
}
function __hxhx_int64_copy($value) {
  $value = __hxhx_int64_value($value);
  return __hxhx_int64_make_u($value->high, $value->low);
}
function __hxhx_int64_is_zero($value) {
  $value = __hxhx_int64_value($value);
  return $value->high === 0 && $value->low === 0;
}
function __hxhx_int64_ucompare($left, $right) {
  $left = __hxhx_int64_value($left);
  $right = __hxhx_int64_value($right);
  $leftHigh = $left->high & 0xFFFFFFFF;
  $rightHigh = $right->high & 0xFFFFFFFF;
  if ($leftHigh < $rightHigh) return -1;
  if ($leftHigh > $rightHigh) return 1;
  $leftLow = $left->low & 0xFFFFFFFF;
  $rightLow = $right->low & 0xFFFFFFFF;
  if ($leftLow < $rightLow) return -1;
  if ($leftLow > $rightLow) return 1;
  return 0;
}
function __hxhx_int64_compare($left, $right) {
  $left = __hxhx_int64_value($left);
  $right = __hxhx_int64_value($right);
  if ($left->high < $right->high) return -1;
  if ($left->high > $right->high) return 1;
  $leftLow = $left->low & 0xFFFFFFFF;
  $rightLow = $right->low & 0xFFFFFFFF;
  if ($leftLow < $rightLow) return -1;
  if ($leftLow > $rightLow) return 1;
  return 0;
}
function __hxhx_int64_shl1($value) {
  $value = __hxhx_int64_value($value);
  $low = ($value->low & 0xFFFFFFFF) << 1;
  $high = (($value->high & 0xFFFFFFFF) << 1) | ((($value->low & 0xFFFFFFFF) >> 31) & 1);
  return __hxhx_int64_make_u($high, $low);
}
function __hxhx_int64_ushr1($value) {
  $value = __hxhx_int64_value($value);
  $high = $value->high & 0xFFFFFFFF;
  $low = $value->low & 0xFFFFFFFF;
  return __hxhx_int64_make_u($high >> 1, (($high & 1) << 31) | ($low >> 1));
}
function __hxhx_int64_shr1($value) {
  $value = __hxhx_int64_value($value);
  $low = $value->low & 0xFFFFFFFF;
  return __hxhx_int64_make_u($value->high >> 1, (($value->high & 1) << 31) | ($low >> 1));
}
function __hxhx_int64_shl($value, $bits) {
  $bits = intval($bits) & 63;
  $value = __hxhx_int64_value($value);
  for ($i = 0; $i < $bits; $i++) $value = __hxhx_int64_shl1($value);
  return $value;
}
function __hxhx_int64_shr($value, $bits) {
  $bits = intval($bits) & 63;
  $value = __hxhx_int64_value($value);
  for ($i = 0; $i < $bits; $i++) $value = __hxhx_int64_shr1($value);
  return $value;
}
function __hxhx_int64_ushr($value, $bits) {
  $bits = intval($bits) & 63;
  $value = __hxhx_int64_value($value);
  for ($i = 0; $i < $bits; $i++) $value = __hxhx_int64_ushr1($value);
  return $value;
}
function __hxhx_int64_add($left, $right) {
  $left = __hxhx_int64_value($left);
  $right = __hxhx_int64_value($right);
  $leftLow = $left->low & 0xFFFFFFFF;
  $rightLow = $right->low & 0xFFFFFFFF;
  $low = $leftLow + $rightLow;
  $carry = $low > 0xFFFFFFFF ? 1 : 0;
  $high = ($left->high & 0xFFFFFFFF) + ($right->high & 0xFFFFFFFF) + $carry;
  return __hxhx_int64_make_u($high, $low);
}
function __hxhx_int64_neg($value) {
  $value = __hxhx_int64_value($value);
  $low = ((~($value->low & 0xFFFFFFFF)) + 1) & 0xFFFFFFFF;
  $high = ((~($value->high & 0xFFFFFFFF)) + (($value->low & 0xFFFFFFFF) === 0 ? 1 : 0)) & 0xFFFFFFFF;
  return __hxhx_int64_make_u($high, $low);
}
function __hxhx_int64_sub($left, $right) {
  return __hxhx_int64_add($left, __hxhx_int64_neg($right));
}
function __hxhx_int64_and($left, $right) {
  $left = __hxhx_int64_value($left);
  $right = __hxhx_int64_value($right);
  return __hxhx_int64_make_u($left->high & $right->high, $left->low & $right->low);
}
function __hxhx_int64_or($left, $right) {
  $left = __hxhx_int64_value($left);
  $right = __hxhx_int64_value($right);
  return __hxhx_int64_make_u($left->high | $right->high, $left->low | $right->low);
}
function __hxhx_int64_xor($left, $right) {
  $left = __hxhx_int64_value($left);
  $right = __hxhx_int64_value($right);
  return __hxhx_int64_make_u($left->high ^ $right->high, $left->low ^ $right->low);
}
function __hxhx_int64_not($value) {
  $value = __hxhx_int64_value($value);
  return __hxhx_int64_make_u(~$value->high, ~$value->low);
}
function __hxhx_int64_to_string($value) {
  $value = __hxhx_int64_value($value);
  if ($value->high === 0 && $value->low === 0) return "0";
  $negative = $value->high < 0;
  if ($negative) {
    if ($value->high === -2147483648 && $value->low === 0) return "-9223372036854775808";
    $value = __hxhx_int64_neg($value);
  }
  $parts = [
    (($value->high & 0xFFFFFFFF) >> 16) & 0xFFFF,
    $value->high & 0xFFFF,
    (($value->low & 0xFFFFFFFF) >> 16) & 0xFFFF,
    $value->low & 0xFFFF
  ];
  $digits = "";
  while ($parts[0] !== 0 || $parts[1] !== 0 || $parts[2] !== 0 || $parts[3] !== 0) {
    $carry = 0;
    for ($i = 0; $i < 4; $i++) {
      $part = $carry * 65536 + $parts[$i];
      $parts[$i] = intdiv($part, 10);
      $carry = $part % 10;
    }
    $digits = chr(48 + $carry) . $digits;
  }
  return $negative ? "-" . $digits : $digits;
}
function __hxhx_int64_div_mod($dividend, $divisor) {
  $dividend = __hxhx_int64_value($dividend);
  $divisor = __hxhx_int64_value($divisor);
  if ($divisor->high === 0 && $divisor->low === 0) throw new \Exception("divide by zero");
  if ($divisor->high === 0 && $divisor->low === 1) {
    return (object)["quotient" => __hxhx_int64_copy($dividend), "modulus" => \haxe\Int64::ofInt(0)];
  }
  $dividendNegative = $dividend->high < 0;
  $divisorNegative = $divisor->high < 0;
  $quotientNegative = $dividendNegative !== $divisorNegative;
  $modulus = $dividendNegative ? __hxhx_int64_neg($dividend) : __hxhx_int64_copy($dividend);
  $divisorAbs = $divisorNegative ? __hxhx_int64_neg($divisor) : __hxhx_int64_copy($divisor);
  $quotient = \haxe\Int64::ofInt(0);
  $mask = \haxe\Int64::ofInt(1);
  while ($divisorAbs->high >= 0) {
    $cmp = __hxhx_int64_ucompare($divisorAbs, $modulus);
    $divisorAbs = __hxhx_int64_shl1($divisorAbs);
    $mask = __hxhx_int64_shl1($mask);
    if ($cmp >= 0) break;
  }
  while (!__hxhx_int64_is_zero($mask)) {
    if (__hxhx_int64_ucompare($modulus, $divisorAbs) >= 0) {
      $quotient = __hxhx_int64_add($quotient, $mask);
      $modulus = __hxhx_int64_sub($modulus, $divisorAbs);
    }
    $mask = __hxhx_int64_ushr1($mask);
    $divisorAbs = __hxhx_int64_ushr1($divisorAbs);
  }
  if ($quotientNegative) $quotient = __hxhx_int64_neg($quotient);
  if ($dividendNegative) $modulus = __hxhx_int64_neg($modulus);
  return (object)["quotient" => $quotient, "modulus" => $modulus];
}
function __hxhx_int64_mul($left, $right) {
  $left = __hxhx_int64_value($left);
  $right = __hxhx_int64_value($right);
  $a0 = $left->low & 0xFFFF;
  $a1 = (($left->low & 0xFFFFFFFF) >> 16) & 0xFFFF;
  $a2 = $left->high & 0xFFFF;
  $a3 = (($left->high & 0xFFFFFFFF) >> 16) & 0xFFFF;
  $b0 = $right->low & 0xFFFF;
  $b1 = (($right->low & 0xFFFFFFFF) >> 16) & 0xFFFF;
  $b2 = $right->high & 0xFFFF;
  $b3 = (($right->high & 0xFFFFFFFF) >> 16) & 0xFFFF;
  $c0 = $a0 * $b0;
  $c1 = ($c0 >> 16) + $a1 * $b0 + $a0 * $b1;
  $c2 = ($c1 >> 16) + $a2 * $b0 + $a1 * $b1 + $a0 * $b2;
  $c3 = ($c2 >> 16) + $a3 * $b0 + $a2 * $b1 + $a1 * $b2 + $a0 * $b3;
  $low = (($c1 & 0xFFFF) << 16) | ($c0 & 0xFFFF);
  $high = (($c3 & 0xFFFF) << 16) | ($c2 & 0xFFFF);
  return __hxhx_int64_make_u($high, $low);
}
function __hxhx_int_literal($text, $suffix) {
  $clean = str_replace("_", "", strtolower($text));
  if (strpos($clean, "0x") === 0) {
    $hex = ltrim(substr($clean, 2), "0");
    if ($hex === "") return 0;
    if (($suffix === "i64" || $suffix === "u64") && strlen($hex) > 16) $hex = substr($hex, -16);
    if (($suffix === "" || $suffix === "i32" || $suffix === "u32") && strlen($hex) > 8) $hex = substr($hex, -8);
    if ($suffix === "" || $suffix === "i32") {
      $value32 = hexdec($hex);
      return $value32 >= 2147483648 ? intval($value32 - 4294967296) : intval($value32);
    }
    if ($suffix === "i64" && strlen($hex) === 16 && hexdec(substr($hex, 0, 1)) >= 8) {
      if ($hex === "ffffffffffffffff") return -1;
      if ($hex === "8000000000000000") return "-9223372036854775808";
      return "-" . strval(hexdec($hex));
    }
    $value = hexdec($hex);
    return is_float($value) ? sprintf("%.0f", $value) : intval($value);
  }
  $negative = strlen($clean) > 0 && $clean[0] === "-";
  $digits = $negative ? substr($clean, 1) : $clean;
  $limit = $negative ? "9223372036854775808" : "9223372036854775807";
  if (strlen($digits) < 19 || (strlen($digits) === 19 && strcmp($digits, $limit) <= 0)) return intval($clean);
  return $clean;
}
