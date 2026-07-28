/// The places where Dart's arithmetic and JavaScript's disagree.
///
/// Upstream is JavaScript, and reproducing it byte for byte means reproducing
/// its number semantics — not the ones Dart would pick. Every function here
/// exists because a direct translation silently produces a different answer.
library;

/// JavaScript's `%`, which is a *remainder*: it keeps the sign of the dividend.
///
/// Dart's `%` is a modulo and is never negative for a positive divisor, so
/// `-7 % 5` is `3` in Dart and `-2` in JavaScript. `remainder` is the matching
/// operation.
///
/// **[divisor] must not be zero.** JavaScript answers `NaN` there and carries
/// on; Dart throws, and this does too. Callers that can see a zero divisor —
/// `pixel` computes `hash % i` starting from `i == 0` — must use
/// [jsModOrNull] instead, which can express the `NaN`.
int jsMod(int value, int divisor) => value.remainder(divisor);

/// [jsMod], but able to express JavaScript's `NaN` for a zero divisor.
///
/// Returns `null` where JavaScript would return `NaN`. Everything downstream
/// of a `NaN` in upstream's pipeline ends up as an absent value — `colors[NaN]`
/// is `undefined`, and React omits the attribute — so `null` is the faithful
/// Dart shape, not a convenience.
int? jsModOrNull(int value, int divisor) =>
    divisor == 0 ? null : value.remainder(divisor);

/// The same as [jsMod], for the float division `getDigit` performs.
double jsModDouble(double value, double divisor) => value.remainder(divisor);

/// Truncates to a signed 32-bit integer, the way any JavaScript bitwise
/// operator does (`ToInt32`).
///
/// Dart integers are 64-bit and never wrap on their own, so this has to be
/// applied wherever upstream relies on a bitwise op to narrow a value.
int toSigned32(int value) => value.toSigned(32);

/// Formats a number the way JavaScript's `String(n)` does.
///
/// This is what upstream's string concatenation produces when it builds an SVG
/// attribute, so a Dart `toString` — which writes `4.0` where JavaScript writes
/// `4` — would break byte parity on the rendered output.
///
/// Three cases need handling beyond Dart's default:
///
/// * **integral values** print without a decimal point;
/// * **negative zero** prints as `0`, because `String(-0)` does;
/// * **large integral values** print in full up to `1e21`, where JavaScript
///   switches to exponential. Dart reaches for exponential far earlier, and
///   `toInt()` would silently saturate at 2^63 — `String(1e19)` is
///   `10000000000000000000`, not `9223372036854775807`.
///
/// Non-integral values already round-trip identically: both languages emit the
/// shortest representation that parses back to the same double.
String jsNum(num value) {
  if (value is int) return value.toString();
  final d = value.toDouble();
  if (d.isNaN) return 'NaN';
  if (d.isInfinite) return d.isNegative ? '-Infinity' : 'Infinity';
  if (d == 0) return '0'; // JavaScript prints -0 as "0"
  if (d == d.truncateToDouble() && d.abs() < 1e21) {
    return d.toStringAsFixed(0);
  }
  return d.toString();
}

/// JavaScript's `parseInt(s, 16)`, per ECMA-262.
///
/// A hand-rolled "scan the leading hex digits" is *not* the same function, and
/// the difference is reachable: a palette entry is consumer policy, and `beam`
/// hands whatever it finds straight to `getContrast`. Four behaviours have to
/// come along:
///
/// * leading whitespace is skipped — `parseInt('\tF', 16)` is `15`;
/// * an optional `+` or `-` sign is consumed — `parseInt('-F', 16)` is `-15`;
/// * with radix 16, a `0x` or `0X` prefix is **stripped**, so `parseInt('0x',
///   16)` finds no digits and is `NaN` — which is why `'0xFF0000'`, the shape a
///   Dart author is most likely to write, contrasts as white and not black;
/// * anything after the leading digit run is ignored.
///
/// Returns [double.nan] when no digits are found. That `NaN` is load-bearing:
/// it propagates through `getContrast`'s arithmetic and makes its comparison
/// false rather than throwing.
double jsParseIntHex(String source) {
  var i = 0;

  while (i < source.length && _isJsWhitespace(source.codeUnitAt(i))) {
    i++;
  }

  var negative = false;
  if (i < source.length) {
    final sign = source.codeUnitAt(i);
    if (sign == 0x2B || sign == 0x2D) {
      negative = sign == 0x2D;
      i++;
    }
  }

  // Radix 16 strips a 0x / 0X prefix before looking for digits.
  if (i + 1 < source.length &&
      source.codeUnitAt(i) == 0x30 &&
      (source.codeUnitAt(i + 1) == 0x78 || source.codeUnitAt(i + 1) == 0x58)) {
    i += 2;
  }

  final start = i;
  while (i < source.length && _isHexDigit(source.codeUnitAt(i))) {
    i++;
  }
  if (i == start) return double.nan;

  final magnitude = int.parse(source.substring(start, i), radix: 16).toDouble();
  return negative ? -magnitude : magnitude;
}

/// The code points ECMA-262 calls `StrWhiteSpace`, which `parseInt` skips.
bool _isJsWhitespace(int c) =>
    c == 0x09 || // tab
    c == 0x0A || // line feed
    c == 0x0B || // vertical tab
    c == 0x0C || // form feed
    c == 0x0D || // carriage return
    c == 0x20 || // space
    c == 0xA0 || // no-break space
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 || // line separator
    c == 0x2029 || // paragraph separator
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF; // zero-width no-break space

bool _isHexDigit(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
    (codeUnit >= 0x41 && codeUnit <= 0x46) || // A-F
    (codeUnit >= 0x61 && codeUnit <= 0x66); // a-f

/// JavaScript's `String.prototype.substr(start, length)`, which clamps instead
/// of throwing when the string is shorter than asked for.
String jsSubstr(String source, int start, int length) {
  if (start >= source.length) return '';
  final end = start + length;
  return source.substring(start, end > source.length ? source.length : end);
}
