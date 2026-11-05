import 'package:bonsoir/bonsoir.dart';

/// Browses `_csdmm._tcp` and yields `http://host:port` for each resolved server.
/// The token is not advertised; the user still scans the QR once to pair.
Stream<String> discoverServers() async* {
  final discovery = BonsoirDiscovery(type: '_csdmm._tcp');
  await discovery.initialize();
  try {
    discovery.start();
    await for (final e in discovery.eventStream!) {
      switch (e) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          service.resolve(discovery.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
          if (service.hostAddress != null) yield 'http://${service.hostAddress}:${service.port}';
        default:
      }
    }
  } finally {
    await discovery.stop();
  }
}
