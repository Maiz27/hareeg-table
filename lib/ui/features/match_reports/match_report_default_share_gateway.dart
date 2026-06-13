/// Selects the platform-appropriate default `MatchReportShareGateway` at
/// compile time: a browser-download gateway on web, the `share_plus` share
/// sheet on native. Re-exported as the const `defaultMatchReportShareGateway`.
library;

export 'match_report_default_share_gateway_native.dart'
    if (dart.library.js_interop) 'match_report_default_share_gateway_web.dart';
