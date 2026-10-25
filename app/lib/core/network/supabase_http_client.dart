import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../supabase_auth_options.dart';
import 'client.dart';

/// Reuse connections while bounding each request independently. Aborting at the
/// transport layer prevents a timed-out login from succeeding later in GoTrue.
class SupabaseHttpClient extends http.BaseClient {
  SupabaseHttpClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 12),
    Duration? readTimeout,
  }) : readTimeout = readTimeout ?? timeout,
       _inner = inner ?? createPlatformClient();

  final http.Client _inner;
  final Duration timeout;
  final Duration readTimeout;
  final Set<Completer<void>> _active = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final cloudBase = request.url.host.endsWith('.api.tcloudbasegateway.com');
    if (cloudBase && request.url.path.endsWith('/auth/v1/logout')) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        204,
        request: request,
      );
    }
    final adaptation = cloudBase
        ? await _adaptCloudBaseRequest(request)
        : _CloudBaseAdaptation(request);
    request = adaptation.request;
    // Only the fixed-project gateway's bodyless reads can be replayed. A write
    // can succeed upstream even when its response is lost, so never retry it.
    final retryableRead =
        (request.url.host == gatewayHost || cloudBase) &&
        (request.method == 'GET' || request.method == 'HEAD') &&
        request.contentLength == 0;
    final deadline = retryableRead ? readTimeout : timeout;
    final watch = Stopwatch()..start();
    final abort = Completer<void>();
    _active.add(abort);
    var timedOut = false;
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    final timer = Timer(deadline, () {
      timedOut = true;
      cancel();
    });
    void finish() {
      timer.cancel();
      _active.remove(abort);
    }

    if (request is http.Abortable && request.abortTrigger != null) {
      unawaited(request.abortTrigger!.then((_) => cancel()));
    }
    Future<http.StreamedResponse> sendOne(http.BaseRequest candidate) async {
      final remaining = deadline - watch.elapsed;
      if (remaining <= Duration.zero || timedOut) {
        throw TimeoutException('连接服务超时', deadline);
      }
      return _inner
          .send(_AbortableRequest(candidate, abort.future))
          .timeout(
            remaining,
            onTimeout: () {
              timedOut = true;
              cancel();
              throw TimeoutException('连接服务超时', deadline);
            },
          );
    }

    try {
      http.StreamedResponse response;
      var retried = false;
      try {
        response = await sendOne(request);
      } on http.ClientException catch (error) {
        if (!retryableRead ||
            error is http.RequestAbortedException ||
            abort.isCompleted) {
          rethrow;
        }
        retried = true;
        response = await sendOne(_copyRead(request));
      }
      if (retryableRead &&
          !retried &&
          !abort.isCompleted &&
          {502, 503, 504}.contains(response.statusCode)) {
        // Gateway errors are safe to retry for GET/HEAD only. Release the first
        // response before opening a replacement request on the same client.
        try {
          await response.stream.drain<void>();
        } on http.ClientException {
          // A broken error body is another transient transport failure.
        }
        response = await sendOne(_copyRead(request));
      }
      Stream<List<int>> body() async* {
        try {
          await for (final bytes in response.stream) {
            if (timedOut) throw TimeoutException('连接服务超时', deadline);
            yield bytes;
          }
          if (timedOut) throw TimeoutException('连接服务超时', deadline);
        } on http.RequestAbortedException {
          if (timedOut) throw TimeoutException('连接服务超时', deadline);
          rethrow;
        } finally {
          finish();
        }
      }

      final streamed = http.StreamedResponse(
        body(),
        response.statusCode,
        headers: response.headers,
        contentLength: response.contentLength,
        request: request,
        reasonPhrase: response.reasonPhrase,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
      );
      if (cloudBase && adaptation.responseKind != _CloudBaseResponseKind.none) {
        return _adaptCloudBaseResponse(streamed, adaptation);
      }
      return streamed;
    } catch (e) {
      finish();
      if (timedOut) throw TimeoutException('连接服务超时', deadline);
      rethrow;
    }
  }

  @override
  void close() {
    for (final abort in _active) {
      if (!abort.isCompleted) abort.complete();
    }
    _active.clear();
    _inner.close();
  }

  Future<http.StreamedResponse> _adaptCloudBaseResponse(
    http.StreamedResponse response,
    _CloudBaseAdaptation adaptation,
  ) async {
    final bytes = await response.stream.toBytes();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _bufferedResponse(response, bytes);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (adaptation.responseKind == _CloudBaseResponseKind.user) {
      final profile = Map<String, dynamic>.from(decoded as Map);
      final transformed = _supabaseUser(profile);
      return _bufferedResponse(response, utf8.encode(jsonEncode(transformed)));
    }
    final token = Map<String, dynamic>.from(decoded as Map);
    Map<String, dynamic>? profile;
    final accessToken = token['access_token'] as String?;
    if (accessToken != null) {
      try {
        final profileRequest = http.Request(
          'GET',
          Uri.parse('https://${response.request!.url.host}/auth/v1/user/me'),
        )..headers['authorization'] = 'Bearer $accessToken';
        final profileResponse = await _inner
            .send(profileRequest)
            .timeout(const Duration(seconds: 5));
        final profileBytes = await profileResponse.stream.toBytes();
        if (profileResponse.statusCode >= 200 &&
            profileResponse.statusCode < 300) {
          profile = Map<String, dynamic>.from(
            jsonDecode(utf8.decode(profileBytes)) as Map,
          );
        }
      } catch (_) {
        // Token login remains usable with the minimal fallback profile.
      }
    }
    profile ??= {
      'sub': token['sub'],
      'email': adaptation.originalEmail,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    token['user'] = _supabaseUser(
      profile,
      fallbackEmail: adaptation.originalEmail,
    );
    return _bufferedResponse(response, utf8.encode(jsonEncode(token)));
  }
}

enum _CloudBaseResponseKind { none, token, user }

class _CloudBaseAdaptation {
  const _CloudBaseAdaptation(
    this.request, {
    this.responseKind = _CloudBaseResponseKind.none,
    this.originalEmail,
  });

  final http.BaseRequest request;
  final _CloudBaseResponseKind responseKind;
  final String? originalEmail;
}

Future<_CloudBaseAdaptation> _adaptCloudBaseRequest(
  http.BaseRequest source,
) async {
  final originalPath = source.url.path;
  var target = source.url;
  var responseKind = _CloudBaseResponseKind.none;
  String? originalEmail;
  Map<String, dynamic>? jsonBody;

  if (originalPath.startsWith('/rest/v1')) {
    target = source.url.replace(
      path: originalPath.replaceFirst('/rest/v1', '/v1/rdb/rest'),
    );
  } else if (originalPath.endsWith('/auth/v1/user')) {
    target = source.url.replace(path: '/auth/v1/user/me');
    responseKind = _CloudBaseResponseKind.user;
  } else if (originalPath.endsWith('/auth/v1/token')) {
    final bytes = await source.finalize().toBytes();
    jsonBody = bytes.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
    final grantType = source.url.queryParameters['grant_type'];
    if (grantType == 'password') {
      originalEmail = jsonBody.remove('email') as String?;
      if (originalEmail != null) {
        jsonBody['username'] = cloudBaseUsernameForEmail(originalEmail);
      }
      jsonBody.remove('gotrue_meta_security');
    }
    if (grantType != null) jsonBody['grant_type'] = grantType;
    target = Uri(
      scheme: source.url.scheme,
      userInfo: source.url.userInfo,
      host: source.url.host,
      port: source.url.hasPort ? source.url.port : null,
      path: source.url.path,
    );
    responseKind = _CloudBaseResponseKind.token;
  }

  if (target == source.url && jsonBody == null) {
    source.headers.remove('apikey');
    return _CloudBaseAdaptation(
      source,
      responseKind: responseKind,
      originalEmail: originalEmail,
    );
  }

  final request = http.Request(source.method, target)
    ..headers.addAll(source.headers)
    ..followRedirects = source.followRedirects
    ..maxRedirects = source.maxRedirects
    ..persistentConnection = source.persistentConnection;
  request.headers.remove('apikey');
  if (responseKind == _CloudBaseResponseKind.token) {
    request.headers.remove('authorization');
  }
  if (jsonBody != null) {
    request.body = jsonEncode(jsonBody);
    request.headers['content-type'] = 'application/json';
  } else if ((source.contentLength ?? 0) > 0) {
    request.bodyBytes = await source.finalize().toBytes();
  }
  return _CloudBaseAdaptation(
    request,
    responseKind: responseKind,
    originalEmail: originalEmail,
  );
}

String cloudBaseUsernameForEmail(String email) {
  final normalized = email
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final username = 'u_$normalized';
  if (normalized.isEmpty || username.length > 48) {
    throw const FormatException('邮箱无法转换为 CloudBase 用户名');
  }
  return username;
}

Map<String, dynamic> _supabaseUser(
  Map<String, dynamic> profile, {
  String? fallbackEmail,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final id = '${profile['sub'] ?? profile['user_id'] ?? ''}';
  final createdAt = '${profile['created_at'] ?? now}';
  return {
    'id': id,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': profile['email'] ?? fallbackEmail,
    'phone': profile['phone_number'],
    'created_at': createdAt,
    'updated_at': profile['updated_at'] ?? createdAt,
    'last_sign_in_at': profile['last_login'],
    'email_confirmed_at': profile['email_verified'] == false ? null : createdAt,
    'app_metadata': {
      'provider': 'cloudbase',
      'providers': ['cloudbase'],
    },
    'user_metadata': {
      'name': profile['name'],
      'username': profile['username'],
      'picture': profile['picture'],
    },
    'identities': <Object>[],
    'is_anonymous': false,
  };
}

http.StreamedResponse _bufferedResponse(
  http.StreamedResponse source,
  List<int> bytes,
) => http.StreamedResponse(
  Stream.value(bytes),
  source.statusCode,
  headers: source.headers,
  contentLength: bytes.length,
  request: source.request,
  reasonPhrase: source.reasonPhrase,
  isRedirect: source.isRedirect,
  persistentConnection: source.persistentConnection,
);

http.Request _copyRead(http.BaseRequest source) =>
    http.Request(source.method, source.url)
      ..headers.addAll(source.headers)
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection;

class _AbortableRequest extends http.BaseRequest with http.Abortable {
  _AbortableRequest(http.BaseRequest source, this.abortTrigger)
    : _body = source.finalize(),
      super(source.method, source.url) {
    headers.addAll(source.headers);
    contentLength = source.contentLength;
    followRedirects = source.followRedirects;
    maxRedirects = source.maxRedirects;
    persistentConnection = source.persistentConnection;
  }

  final http.ByteStream _body;
  @override
  final Future<void> abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return _body;
  }
}
