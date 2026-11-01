import 'package:http/http.dart' as http;
import 'client_stub.dart' if (dart.library.io) 'client_io.dart' as platform;

http.Client createPlatformClient() => platform.createClient();
