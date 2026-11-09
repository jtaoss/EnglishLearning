import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'specs/config_flow.dart' as config;
import 'specs/local_learning.dart' as learning;
import 'specs/starter_flow.dart' as theme;
import 'specs/file_import.dart' as file_import;
import 'specs/cold_restart.dart' as cold_restart;
import 'specs/pronunciation.dart' as pronunciation;
import 'specs/pronunciation_cold.dart' as pronunciation_cold;
import 'specs/notion_sync.dart' as notion;
import 'specs/notion_cold.dart' as notion_cold;
import 'specs/notion_live.dart' as notion_live;
import 'specs/notion_live_cold.dart' as notion_live_cold;
import 'specs/notion_live_personal.dart' as notion_live_personal;
import 'specs/p1d_learning.dart' as p1d_learning;
import 'specs/p1d_cold.dart' as p1d_cold;
import 'specs/p1d_sync.dart' as p1d_sync;
import 'specs/p2a_events.dart' as p2a_events;
import 'specs/p2b1_copy.dart' as p2b1_copy;
import 'specs/android_live.dart' as android_live;
import 'specs/p3_windows.dart' as p3_windows;
import 'specs/p3_live.dart' as p3_live;
import 'specs/p3_cloud_snapshot.dart' as p3_cloud_snapshot;
import 'specs/p4_learning.dart' as p4_learning;
import 'specs/p41_trial.dart' as p41_trial;

/// One native launch avoids reusing Flutter 3.47.7's closed desktop log reader.
/// Original assertions remain in separate specification modules.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('configuration', config.main);
  group('local learning', learning.main);
  group('native theme', theme.main);
  group('native file import', file_import.main);
  group('native restart', cold_restart.main);
  group('native pronunciation', pronunciation.main);
  group('native pronunciation restart', pronunciation_cold.main);
  group('native Notion replay', notion.main);
  group('native Notion restart', notion_cold.main);
  group('native Notion live', notion_live.main);
  group('native Notion live restart', notion_live_cold.main);
  group('native Notion live personal', notion_live_personal.main);
  group('P1-D learning', p1d_learning.main);
  group('P1-D restart', p1d_cold.main);
  group('P1-D sync boundary', p1d_sync.main);
  group('P2-A events', p2a_events.main);
  group('P2-B1 copy', p2b1_copy.main);
  group('Android device', android_live.main);
  group('P3 Windows', p3_windows.main);
  group('P3 live Notion', p3_live.main);
  group('P3 cloud snapshot', p3_cloud_snapshot.main);
  group('P4 actual learning', p4_learning.main);
  group('P4.1 personal trial', p41_trial.main);
}
