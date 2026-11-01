/// Why a path cannot ride in a referrer.
///
/// The builder is never more permissive than the app's
/// `InstallReferrer.deepLink(allow: …, hosts: …)` in
/// `imaji_install_attribution`: every path the app would drop (so the
/// install would land on the home screen) is refused. It is stricter in two
/// places, because emitting such a path is a bug even when the app copes:
/// leading or trailing whitespace, which the app trims
/// ([surroundingWhitespace]), and a `.`/`..` segment, which the URI parser
/// removes before the app checks segments ([unsafe]).
enum PathRefusal {
  /// The path is empty.
  empty,

  /// The path has leading or trailing whitespace.
  surroundingWhitespace,

  /// The path contains a backslash or a control character.
  forbiddenCharacter,

  /// The path cannot be parsed as a URI reference.
  malformed,

  /// The value does not start with `/` and is not an `https` URL.
  notAPath,

  /// The value is an absolute or protocol-relative URL that is not `https`
  /// on one of the allowed hosts, or that carries a port or user info.
  hostNotAllowed,

  /// The path starts with `//`, or has a `.` or `..` segment (also when
  /// percent-encoded), or a segment that cannot be decoded.
  unsafe,

  /// The path is not equal to, or below, any of the allowed prefixes.
  notAllowlisted,
}

/// The outcome of checking one path: the link the app would route, or why
/// it would not route one.
typedef PathCheck = ({Uri? link, PathRefusal? refusal});

/// Checks [value] with the same rules as the app's
/// `InstallReferrer.resolveDeepLink`, plus the builder-only whitespace and
/// dot-segment rules.
///
/// Returns the deep link the app will produce from [value] after one decode,
/// or the reason it would produce none.
PathCheck resolvePath(
  String value, {
  required Iterable<String> allow,
  Iterable<String> hosts = const [],
}) {
  PathCheck refuse(PathRefusal reason) => (link: null, refusal: reason);

  if (value.isEmpty) return refuse(PathRefusal.empty);
  final text = value.trim();
  if (text.isEmpty) return refuse(PathRefusal.empty);
  if (text != value) return refuse(PathRefusal.surroundingWhitespace);
  if (text.contains(r'\')) return refuse(PathRefusal.forbiddenCharacter);
  if (text.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
    return refuse(PathRefusal.forbiddenCharacter);
  }

  // Builder-only: the URI parser below removes `.`/`..` segments (also
  // percent-encoded ones) before the app's own segment check sees them, so
  // `/items/../admin` reaches the app as `/admin`. A builder that emits a
  // dot segment has a bug either way; refuse it while it is still visible.
  final rawPath = text.split(RegExp('[?#]')).first;
  for (final segment in rawPath.split('/')) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(segment);
    } on ArgumentError {
      continue; // judged after parsing, exactly as the app does
    }
    if (decoded == '.' || decoded == '..') return refuse(PathRefusal.unsafe);
  }

  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return refuse(PathRefusal.malformed);
  }

  if (uri.hasScheme || text.startsWith('//')) {
    final allowedHosts = {for (final h in hosts) h.toLowerCase()};
    final ok =
        uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        allowedHosts.contains(uri.host.toLowerCase());
    if (!ok) return refuse(PathRefusal.hostNotAllowed);
  } else if (!text.startsWith('/')) {
    return refuse(PathRefusal.notAPath);
  }

  final path = uri.path;
  if (!path.startsWith('/') || path.startsWith('//')) {
    return refuse(PathRefusal.unsafe);
  }
  for (final segment in path.split('/')) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(segment);
    } on ArgumentError {
      return refuse(PathRefusal.unsafe);
    }
    if (decoded == '.' || decoded == '..') return refuse(PathRefusal.unsafe);
  }

  if (!allow.any((prefix) => _matchesPrefix(path, prefix))) {
    return refuse(PathRefusal.notAllowlisted);
  }

  return (
    link: Uri(
      path: path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ),
    refusal: null,
  );
}

/// The app's prefix rule: `/items` and `/items/` both allow `/items` and
/// `/items/42`, never `/itemsX`; `/` allows every path; a prefix that does
/// not start with `/` allows nothing.
bool _matchesPrefix(String path, String prefix) {
  if (!prefix.startsWith('/')) return false;
  if (prefix == '/') return true;
  final base = prefix.endsWith('/')
      ? prefix.substring(0, prefix.length - 1)
      : prefix;
  return path == base || path.startsWith('$base/');
}
