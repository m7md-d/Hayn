import 'package:integration_test/integration_test_driver.dart';

// Host side of `flutter drive` for the integration tests (profile mode). The
// report carries the artifacts, which matter most when a test fails.
Future<void> main() => integrationDriver(writeResponseOnFailure: true);
