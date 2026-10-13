import 'dart:async';
import 'package:http/http.dart' as http;
import 'client.dart';

/// Reuse connections while bounding each request independently. Aborting at the
/// transport layer prevents a timed-out login from succeeding later in GoTrue.
class SupabaseHttpClient extends http.BaseClient {
  SupabaseHttpClient(
      {http.Client? inner, this.timeout = const Duration(seconds: 12)})
      : _inner = inner ?? createPlatformClient();

  final http.Client _inner;
  final Duration timeout;
  final Set<Completer<void>> _active = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abort = Completer<void>();
    _active.add(abort);
    var timedOut = false;
    void cancel() {
      if (!abort.isCompleted) abort.complete();
    }

    final timer = Timer(timeout, () {
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
    try {
      final wrapped = _AbortableRequest(request, abort.future);
      final response =
          await _inner.send(wrapped).timeout(timeout, onTimeout: () {
        timedOut = true;
        cancel();
        throw TimeoutException('连接服务超时', timeout);
      });
      Stream<List<int>> body() async* {
        try {
          await for (final bytes in response.stream) {
            if (timedOut) throw TimeoutException('连接服务超时', timeout);
            yield bytes;
          }
          if (timedOut) throw TimeoutException('连接服务超时', timeout);
        } on http.RequestAbortedException {
          if (timedOut) throw TimeoutException('连接服务超时', timeout);
          rethrow;
        } finally {
          finish();
        }
      }

      return http.StreamedResponse(body(), response.statusCode,
          headers: response.headers,
          contentLength: response.contentLength,
          request: request,
          reasonPhrase: response.reasonPhrase,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection);
    } catch (e) {
      finish();
      if (timedOut) throw TimeoutException('连接服务超时', timeout);
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
