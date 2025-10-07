// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math' show Random;

/// Generates a pseudo-random ID string with 32 bits of entropy.
String generateId() {
  final chars = List<int>.filled(6, 0);
  final random = Random();
  var bits = random.nextInt(0x100000000);
  for (var i = 0; i < 6; i++) {
    chars[i] = _base64Chars.codeUnitAt(bits & 0x3F);
    bits >>>= 6;
  }
  return String.fromCharCodes(chars);
}

// A standard encoding of 6 bits per character, without any non-ASCII,
// non-printable or disallowed characters.
const _base64Chars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/// HTTP status codes and helpers (no dart:io).
/// Includes browser-focused helpers per WHATWG Fetch.
class HttpStatus {
  // --- Informational ---
  static const int continue_ = 100;
  static const int switchingProtocols = 101;
  static const int processing = 102;
  static const int earlyHints = 103;

  // --- Success ---
  static const int ok = 200;
  static const int created = 201;
  static const int accepted = 202;
  static const int nonAuthoritativeInformation = 203;
  static const int noContent = 204;
  static const int resetContent = 205;
  static const int partialContent = 206;
  static const int multiStatus = 207;
  static const int alreadyReported = 208;
  static const int imUsed = 226;

  // --- Redirection ---
  static const int multipleChoices = 300;
  static const int movedPermanently = 301;
  static const int found = 302;
  static const int seeOther = 303;
  static const int notModified = 304;
  static const int useProxy = 305;
  static const int temporaryRedirect = 307;
  static const int permanentRedirect = 308;

  // --- Client Error ---
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int paymentRequired = 402;
  static const int forbidden = 403;
  static const int notFound = 404;
  static const int methodNotAllowed = 405;
  static const int notAcceptable = 406;
  static const int proxyAuthenticationRequired = 407;
  static const int requestTimeout = 408;
  static const int conflict = 409;
  static const int gone = 410;
  static const int lengthRequired = 411;
  static const int preconditionFailed = 412;
  static const int payloadTooLarge = 413;
  static const int uriTooLong = 414;
  static const int unsupportedMediaType = 415;
  static const int rangeNotSatisfiable = 416;
  static const int expectationFailed = 417;
  static const int misdirectedRequest = 421;
  static const int unprocessableEntity = 422;
  static const int locked = 423;
  static const int failedDependency = 424;
  static const int tooEarly = 425;
  static const int upgradeRequired = 426;
  static const int preconditionRequired = 428;
  static const int tooManyRequests = 429;
  static const int requestHeaderFieldsTooLarge = 431;
  static const int unavailableForLegalReasons = 451;

  // --- Server Error ---
  static const int internalServerError = 500;
  static const int notImplemented = 501;
  static const int badGateway = 502;
  static const int serviceUnavailable = 503;
  static const int gatewayTimeout = 504;
  static const int httpVersionNotSupported = 505;
  static const int variantAlsoNegotiates = 506;
  static const int insufficientStorage = 507;
  static const int loopDetected = 508;
  static const int notExtended = 510;
  static const int networkAuthenticationRequired = 511;

  static const Map<int, String> _reasons = {
    // Informational
    continue_: "Continue",
    switchingProtocols: "Switching Protocols",
    processing: "Processing",
    earlyHints: "Early Hints",
    // Success
    ok: "OK",
    created: "Created",
    accepted: "Accepted",
    nonAuthoritativeInformation: "Non-Authoritative Information",
    noContent: "No Content",
    resetContent: "Reset Content",
    partialContent: "Partial Content",
    multiStatus: "Multi-Status",
    alreadyReported: "Already Reported",
    imUsed: "IM Used",
    // Redirection
    multipleChoices: "Multiple Choices",
    movedPermanently: "Moved Permanently",
    found: "Found",
    seeOther: "See Other",
    notModified: "Not Modified",
    useProxy: "Use Proxy",
    temporaryRedirect: "Temporary Redirect",
    permanentRedirect: "Permanent Redirect",
    // Client error
    badRequest: "Bad Request",
    unauthorized: "Unauthorized",
    paymentRequired: "Payment Required",
    forbidden: "Forbidden",
    notFound: "Not Found",
    methodNotAllowed: "Method Not Allowed",
    notAcceptable: "Not Acceptable",
    proxyAuthenticationRequired: "Proxy Authentication Required",
    requestTimeout: "Request Timeout",
    conflict: "Conflict",
    gone: "Gone",
    lengthRequired: "Length Required",
    preconditionFailed: "Precondition Failed",
    payloadTooLarge: "Payload Too Large",
    uriTooLong: "URI Too Long",
    unsupportedMediaType: "Unsupported Media Type",
    rangeNotSatisfiable: "Range Not Satisfiable",
    expectationFailed: "Expectation Failed",
    misdirectedRequest: "Misdirected Request",
    unprocessableEntity: "Unprocessable Entity",
    locked: "Locked",
    failedDependency: "Failed Dependency",
    tooEarly: "Too Early",
    upgradeRequired: "Upgrade Required",
    preconditionRequired: "Precondition Required",
    tooManyRequests: "Too Many Requests",
    requestHeaderFieldsTooLarge: "Request Header Fields Too Large",
    unavailableForLegalReasons: "Unavailable For Legal Reasons",
    // Server error
    internalServerError: "Internal Server Error",
    notImplemented: "Not Implemented",
    badGateway: "Bad Gateway",
    serviceUnavailable: "Service Unavailable",
    gatewayTimeout: "Gateway Timeout",
    httpVersionNotSupported: "HTTP Version Not Supported",
    variantAlsoNegotiates: "Variant Also Negotiates",
    insufficientStorage: "Insufficient Storage",
    loopDetected: "Loop Detected",
    notExtended: "Not Extended",
    networkAuthenticationRequired: "Network Authentication Required",
  };

  static String? reasonPhrase(int code) => _reasons[code];

  // ---- Browser-focused helpers (Fetch spec) ----

  /// `true` if you can construct a `Response` with this status in the browser.
  /// Per Fetch, Response(status) must be in [200, 599].
  static bool isBrowserConstructible(int code) =>
      code >= 200 &&
      code <=
          599; //  [oai_citation:0‡Fetch Standard](https://fetch.spec.whatwg.org/)

  /// `true` if this status must NOT have a body (101, 103, 204, 205, 304).
  static bool isNullBodyStatus(int code) =>
      code == 101 ||
      code == 103 ||
      code == 204 ||
      code == 205 ||
      code ==
          304; //  [oai_citation:1‡Fetch Standard](https://fetch.spec.whatwg.org/)

  static bool isOk(int code) =>
      code >= 200 &&
      code <=
          299; // Fetch “ok status”.  [oai_citation:2‡Fetch Standard](https://fetch.spec.whatwg.org/)
  static bool isRedirect(int code) =>
      code == 301 ||
      code == 302 ||
      code == 303 ||
      code == 307 ||
      code ==
          308; //  [oai_citation:3‡Fetch Standard](https://fetch.spec.whatwg.org/)
}

/// Common HTTP header field names (lowercase), plus helpers for the web.
/// Mirrors common names used by dart:io/http_parser but is safe for web.
class HttpHeaders {
  // --- General ---
  static const String cacheControl = "cache-control";
  static const String connection = "connection";
  static const String date = "date";
  static const String pragma = "pragma";
  static const String trailer = "trailer";
  static const String transferEncoding = "transfer-encoding";
  static const String upgrade = "upgrade";
  static const String via = "via";
  static const String warning = "warning";

  // --- Request ---
  static const String accept = "accept";
  static const String acceptCharset = "accept-charset";
  static const String acceptEncoding = "accept-encoding";
  static const String acceptLanguage = "accept-language";
  static const String authorization = "authorization";
  static const String cookie = "cookie";
  static const String expect = "expect";
  static const String from = "from";
  static const String host = "host";
  static const String ifMatch = "if-match";
  static const String ifModifiedSince = "if-modified-since";
  static const String ifNoneMatch = "if-none-match";
  static const String ifRange = "if-range";
  static const String ifUnmodifiedSince = "if-unmodified-since";
  static const String maxForwards = "max-forwards";
  static const String origin = "origin";
  static const String proxyAuthorization = "proxy-authorization";
  static const String range = "range";
  static const String referer = "referer";
  static const String te = "te";
  static const String userAgent = "user-agent";

  // --- Response ---
  static const String acceptRanges = "accept-ranges";
  static const String age = "age";
  static const String etag = "etag";
  static const String location = "location";
  static const String proxyAuthenticate = "proxy-authenticate";
  static const String retryAfter = "retry-after";
  static const String server = "server";
  static const String vary = "vary";
  static const String wwwAuthenticate = "www-authenticate";
  static const String setCookie = "set-cookie";

  // --- Entity ---
  static const String allow = "allow";
  static const String contentEncoding = "content-encoding";
  static const String contentLanguage = "content-language";
  static const String contentLength = "content-length";
  static const String contentLocation = "content-location";
  static const String contentMD5 = "content-md5"; // legacy
  static const String contentRange = "content-range";
  static const String contentType = "content-type";
  static const String expires = "expires";
  static const String lastModified = "last-modified";

  /// Canonical casing map (e.g., "content-type" -> "Content-Type").
  static const Map<String, String> _canonical = {
    cacheControl: "Cache-Control",
    connection: "Connection",
    date: "Date",
    pragma: "Pragma",
    trailer: "Trailer",
    transferEncoding: "Transfer-Encoding",
    upgrade: "Upgrade",
    via: "Via",
    warning: "Warning",
    accept: "Accept",
    acceptCharset: "Accept-Charset",
    acceptEncoding: "Accept-Encoding",
    acceptLanguage: "Accept-Language",
    authorization: "Authorization",
    cookie: "Cookie",
    expect: "Expect",
    from: "From",
    host: "Host",
    ifMatch: "If-Match",
    ifModifiedSince: "If-Modified-Since",
    ifNoneMatch: "If-None-Match",
    ifRange: "If-Range",
    ifUnmodifiedSince: "If-Unmodified-Since",
    maxForwards: "Max-Forwards",
    origin: "Origin",
    proxyAuthorization: "Proxy-Authorization",
    range: "Range",
    referer: "Referer",
    te: "TE",
    userAgent: "User-Agent",
    acceptRanges: "Accept-Ranges",
    age: "Age",
    etag: "ETag",
    location: "Location",
    proxyAuthenticate: "Proxy-Authenticate",
    retryAfter: "Retry-After",
    server: "Server",
    vary: "Vary",
    wwwAuthenticate: "WWW-Authenticate",
    setCookie: "Set-Cookie",
    allow: "Allow",
    contentEncoding: "Content-Encoding",
    contentLanguage: "Content-Language",
    contentLength: "Content-Length",
    contentLocation: "Content-Location",
    contentMD5: "Content-MD5",
    contentRange: "Content-Range",
    contentType: "Content-Type",
    expires: "Expires",
    lastModified: "Last-Modified",
  };

  static String? canonicalName(String name) => _canonical[name.toLowerCase()];

  // ---------- Browser safety per WHATWG Fetch ----------

  /// Headers JS **cannot set** in the browser (forbidden request headers).
  /// See Fetch spec / MDN for the definitive list.
  static final Set<String> _forbiddenRequest = {
    "accept-charset",
    "accept-encoding",
    "access-control-request-headers",
    "access-control-request-method",
    "connection",
    "content-length",
    "cookie",
    "cookie2", // historical
    "date",
    "dnt",
    "expect",
    "host",
    "keep-alive",
    "origin",
    "permissions-policy", // formerly feature/permissions policy
    "referer",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",
    "via",
    // any header starting with:
    // "proxy-" or "sec-" are also forbidden to set
  };

  /// `true` if this header name is forbidden to set on requests in the browser.
  static bool isForbiddenRequestHeader(String name) {
    final n = name.toLowerCase();
    return _forbiddenRequest.contains(n) ||
        n.startsWith("proxy-") ||
        n.startsWith(
          "sec-",
        ); //  [oai_citation:4‡MDN Web Docs](https://developer.mozilla.org/en-US/docs/Glossary/Forbidden_header_name)
  }

  /// Response headers the browser forbids scripts from modifying.
  static bool isForbiddenResponseHeader(String name) {
    final n = name.toLowerCase();
    return n == "set-cookie" ||
        n ==
            "set-cookie2"; //  [oai_citation:5‡Fetch Standard](https://fetch.spec.whatwg.org/?utm_source=chatgpt.com)
  }

  /// `true` if you can set this header from browser JS (Fetch/XHR).
  static bool isBrowserSettable(String name) => !isForbiddenRequestHeader(name);

  /// A convenience set of **commonly safe** request headers to set in the browser.
  /// (CORS may still block them depending on server policy.)
  static const Set<String> commonlySafeToSet = {
    accept,
    acceptLanguage,
    contentLanguage,
    contentType,
    authorization,
    ifNoneMatch,
    ifModifiedSince,
    range,
    referer, // modify via RequestInit.referrer, but listed here for logging
    userAgent, // allowed by spec now, but some UAs still drop it
  };
}
