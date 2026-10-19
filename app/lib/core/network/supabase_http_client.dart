import 'dart:async';
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
    // Only the fixed-project gateway's bodyless reads can be replayed. A write
    // can succeed upstream even when its response is lost, so never retry it.
    final retryableRead =
        request.url.host == gatewayHost &&
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

      return http.StreamedResponse(
        body(),
        response.statusCode,
        headers: response.headers,
        contentLength: response.contentLength,
        request: request,
        reasonPhrase: response.reasonPhrase,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
      );
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
}

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
