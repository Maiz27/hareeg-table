import 'match_report_exporter.dart';
import 'match_report_web_download.dart';

/// Web default: save the report as a file download (see
/// [WebDownloadMatchReportShareGateway]). `share_plus` has no reliable
/// file-share target in desktop browsers.
const MatchReportShareGateway defaultMatchReportShareGateway =
    WebDownloadMatchReportShareGateway();
