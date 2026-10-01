import 'package:director/models/models.dart';
import 'package:director/screens/home_screen.dart';
import 'package:director/services/api_service.dart';
import 'package:director/services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 导播台主界面在窄窗口下会溢出。
///
/// 复现的是真实报错：可用高度只有 142.8px，而「预设按钮区」里三个固定高度
/// 控件（状态条 + 滑动确认 + 确认按钮）加三个 8px 间距就占了 164px。
/// RenderFlex 溢出 22px 时只会在控制台画黄黑条，**不会中断操作**——对直播
/// 来说这比崩溃更糟：按钮被裁掉一半，导播可能按不到「确认已切」。
///
/// 根因是弹性比例：预设区 flex:3、聊天区 flex:2，两者平分剩余高度。但预设区
/// 是主操作流程、聊天是次要的，比例配反了。
class FakeApiService extends ApiService {
  FakeApiService({this.cameras = const <String>[]});

  final List<String> cameras;

  @override
  Future<List<Project>> getProjects() async => [
    Project(id: 1, name: '秋季运动会', code: 'sp2026', description: ''),
  ];

  @override
  Future<List<ProjectCamera>> getCameras(int projectId) async => [
    for (var i = 0; i < cameras.length; i++)
      ProjectCamera(id: i + 1, name: cameras[i]),
  ];

  @override
  Future<List<InterviewPoint>> getInterviewStatuses(int projectId) async => [
    InterviewPoint(
      id: 1,
      pointCode: 'P1',
      pointName: '1000米',
      status: 'ready',
    ),
    InterviewPoint(
      id: 2,
      pointCode: 'P2',
      pointName: '跳远',
      status: 'preparing',
    ),
  ];

  @override
  Future<Map<String, dynamic>> acquireLock(int projectId) async => {
    'acquired': true,
  };

  @override
  Future<Map<String, dynamic>> releaseLock(int projectId) async => {
    'released': true,
  };

  @override
  Future<Map<String, dynamic>> heartbeat(int projectId) async => {'ok': true};
}

/// 不做任何事的 WebSocket 客户端。测试里绝不能真去连 wss://。
class FakeWebSocketService extends WebSocketService {
  @override
  void connect({required String token, required int projectId}) {}
}

Widget _app({required List<String> cameras}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeScreen(
        apiService: FakeApiService(cameras: cameras),
        wsService: FakeWebSocketService(),
        token: 'test-token',
        user: const {'id': 1, 'username': 'boss', 'display_name': '导播'},
      ),
    ),
  );
}

/// 抓取 Flutter 的布局异常。
///
/// overflow 本身不是 throw，只会把异常交给 FlutterError.onError，所以必须
/// 显式接管并记录，否则测试会「通过」而问题仍在。
List<FlutterErrorDetails> _captureErrors() {
  final caught = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => caught.add(details);
  addTearDown(() => FlutterError.onError = previous);
  return caught;
}

bool _hasOverflow(List<FlutterErrorDetails> errors) {
  return errors.any(
    (e) =>
        e.exception is FlutterError &&
        e.exception.toString().contains('overflowed'),
  );
}

void main() {
  // 报出的是 336x（很窄的窗口）。用 336x760 复现同一个约束。
  //
  // 高度是真正的触发条件：实测 1280x520 正常、1280x480 开始溢出。窄宽度的
  // 窗口（336）也会同时触发，两种都留着当回归用例。
  const narrow = Size(336, 760);
  const wide = Size(1280, 800);
  // 矮窗口：单栏布局在这里会溢出
  const shortWindow = Size(1280, 460);
  // 平板竖屏（768x1024）与手机横屏（844x390）
  const tablet = Size(768, 1024);
  const phoneLandscape = Size(844, 390);
  const cameras = <String>[
    '全景', '50米', '1000米',
    '20×50接力', '跳远', '跳高',
    '跳长绳', '韵律操', '领导讲话',
  ];

  testWidgets('窄窗口下不溢出（回归：预设区固定控件曾超出 22px）', (tester) async {
    final errors = _captureErrors();
    tester.view.physicalSize = narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(cameras: cameras));
    await tester.pump();
    // 让项目列表与机位加载完（都是 Future，微任务里 resolve）
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _hasOverflow(errors),
      isFalse,
      reason: '窄窗口出现 RenderFlex 溢出：\n'
          '${errors.map((e) => e.exception).join('\n')}',
    );
  });

  testWidgets('常规窗口（1280x800）不溢出', (tester) async {
    final errors = _captureErrors();
    tester.view.physicalSize = wide;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(cameras: cameras));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_hasOverflow(errors), isFalse);
  });

  testWidgets('机位很多时也不溢出（网格应滚动而不是撑高父级）', (tester) async {
    final errors = _captureErrors();
    tester.view.physicalSize = narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(cameras: List.generate(24, (i) => '机位${i + 1}')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_hasOverflow(errors), isFalse);
  });

  testWidgets('矮窗口不溢出（回归：单栏在高度 <=480 时溢出 22px）', (tester) async {
    final errors = _captureErrors();
    tester.view.physicalSize = shortWindow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(cameras: cameras));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      _hasOverflow(errors),
      isFalse,
      reason: '矮窗口出现 RenderFlex 溢出：\n'
          '${errors.map((e) => e.exception).join('\n')}',
    );
  });

  testWidgets('平板与手机横屏走两栏布局', (tester) async {
    for (final size in [tablet, phoneLandscape]) {
      final errors = _captureErrors();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(cameras: cameras));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        _hasOverflow(errors),
        isFalse,
        reason: '${size.width}x${size.height} 出现溢出：\n'
            '${errors.map((e) => e.exception).join('\n')}',
      );

      // 两栏布局的判定标志：存在一个横向的 Row 把切换区与聊天区并排。
      // 只断言不溢出是不够的——那会漏掉「退化成单栏」这种静默失效。
      final rows = tester.widgetList<Row>(find.byType(Row)).toList();
      expect(
        rows.any((r) => r.crossAxisAlignment == CrossAxisAlignment.stretch),
        isTrue,
        reason: '${size.width}x${size.height} 应使用左右两栏布局',
      );
    }
  });

  testWidgets('没有可用机位时也不溢出（兜底列表为空）', (tester) async {
    final errors = _captureErrors();
    tester.view.physicalSize = narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(cameras: const []));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(_hasOverflow(errors), isFalse);
  });
}
