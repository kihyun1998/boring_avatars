/// A port of upstream `boring-avatars`' `src/lib/utilities.js`.
///
/// **This is the sacred surface.** Every avatar this package draws is derived
/// from these six functions, and a value that is wrong here is wrong in every
/// variant and every version at once. Worse, it is wrong *irreversibly*: once a
/// release ships, correcting a value changes the avatar of every user of every
/// app that depends on it.
///
/// Nothing here is derived from first principles. Each function reproduces what
/// upstream does, including where that is odd, and the tests assert against
/// values dumped from upstream's own module rather than against anyone's
/// reading of it.
///
/// **Two of upstream's exports are deliberately absent.** `getModulus` and
/// `getAngle` are exported by `utilities.js` and imported by no component at
/// v1.6.1 — `getModulus` is not even called by the other utilities. Porting
/// them would be porting code no caller can reach, the same judgement that
/// closed the `turbulence` variant.
library;

import 'dart:math' as math;

import 'js_number.dart';

/// Upstream `hashCode` — every avatar in the package starts here.
///
/// The `hash = hash & hash` line in the original looks like a no-op and is not.
/// `hash << 5` narrows to 32 bits, but the `- hash` and `+ character` that
/// follow run in float64 and escape that range again; the bitwise AND is what
/// pulls the value back each iteration. A Dart translation that drops it keeps
/// widening a 64-bit integer and diverges on any name long enough to overflow.
///
/// Iteration is over UTF-16 **code units**, matching `charCodeAt` and
/// `String.length`. A surrogate pair counts twice, which is why an emoji hashes
/// differently from a single character.
int jsHashCode(String name) {
  var hash = 0;
  for (var i = 0; i < name.length; i++) {
    final character = name.codeUnitAt(i);
    hash = toSigned32(toSigned32(hash << 5) - hash + character);
  }
  // Note the absence of a further narrowing: JavaScript's Math.abs of the most
  // negative 32-bit value is 2147483648, which does not fit back into int32.
  return hash.abs();
}

/// Upstream `getDigit` — the `ntn`-th decimal digit of [number], from the right.
///
/// The division is **floating point**, not integer: upstream writes
/// `number / Math.pow(10, ntn)`. Using `~/` here produces different digits.
int jsGetDigit(int number, int ntn) {
  final scaled = number / math.pow(10, ntn).toDouble();
  return jsModDouble(scaled, 10).floor();
}

/// Upstream `getBoolean` — whether the `ntn`-th digit is even.
///
/// Upstream writes `!(getDigit(...) % 2)`, and JavaScript's `!` on a number is
/// "is it zero".
bool jsGetBoolean(int number, int ntn) =>
    jsMod(jsGetDigit(number, ntn), 2) == 0;

/// Upstream `getUnit` — a bounded value, optionally negated.
///
/// The negation is gated on `if (index && …)`, and JavaScript treats **`0` as
/// falsy**. A Dart translation of the form `if (index != null && …)` therefore
/// negates where upstream does not, whenever the caller passes `0`. No caller
/// does today; the guard is here because the difference is invisible until one
/// does.
int jsGetUnit(int number, int range, [int? index]) {
  final value = jsMod(number, range);
  if (index != null && index != 0 && jsMod(jsGetDigit(number, index), 2) == 0) {
    return -value;
  }
  return value;
}

/// Upstream `getRandomColor` — indexes [colors] with `number % range`.
///
/// Returns `null` where upstream returns `undefined`, which happens whenever
/// [range] is zero: `number % 0` is `NaN` in JavaScript and `colors[NaN]` is
/// absent. Dart's own `%` would throw instead, so the guard is what keeps an
/// empty palette degrading rather than crashing — matching five of the six
/// variants. (`beam` does crash, because it hands this `null` to
/// [jsGetContrast]; that is upstream's behaviour too.)
String? jsGetRandomColor(int number, List<String> colors, int range) {
  if (range == 0) return null;
  final index = jsMod(number, range);
  if (index < 0 || index >= colors.length) return null;
  return colors[index];
}

/// Upstream `getContrast` — black or white, whichever reads on [hexcolor].
///
/// A leading `#` is optional. Malformed input does **not** throw: `parseInt`
/// yields `NaN`, the YIQ arithmetic propagates it, and `NaN >= 128` is false,
/// so upstream falls through to white. Reproducing that matters — `beam` feeds
/// this whatever `getRandomColor` returned.
String jsGetContrast(String hexcolor) {
  var hex = hexcolor;
  if (hex.startsWith('#')) hex = hex.substring(1);

  final r = jsParseIntHex(jsSubstr(hex, 0, 2));
  final g = jsParseIntHex(jsSubstr(hex, 2, 2));
  final b = jsParseIntHex(jsSubstr(hex, 4, 2));

  final yiq = ((r * 299) + (g * 587) + (b * 114)) / 1000;
  return yiq >= 128 ? '#000000' : '#FFFFFF';
}
