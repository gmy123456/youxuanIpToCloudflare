import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() => runApp(const CfAiUltimateApp());

// ==========================================
// 1. 数据模型与 AI 服务
// ==========================================
class IpResult {
  final String ip;
  int latency;
  final bool isIpv6;
  IpResult({required this.ip, this.latency = 9999, required this.isIpv6});
}

class ApiService {
  static const String apiKey = "yourApi";
  static const String baseUrl =
      "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions";

  static Future<String> generateReview({
    required String product,
    required String tags,
    required String style,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(baseUrl),
            headers: {
              "Authorization": "Bearer $apiKey",
              "Content-Type": "application/json",
            },
            body: jsonEncode({
              "model": "qwen-flash",
              "messages": [
                {"role": "system", "content": "你是一个网购评价助手。输出自然、真实的评价，不要带有AI味。"},
                {
                  "role": "user",
                  "content": "商品：$product，标签：$tags，风格：$style。请写一段60字左右的评价。",
                },
              ],
              "temperature": 0.8,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        var data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'];
      }
      return "生成失败 (状态码: ${response.statusCode})";
    } catch (e) {
      return "网络异常: $e";
    }
  }
}

// ==========================================
// 2. 主框架 (Tab 切换)
// ==========================================
class CfAiUltimateApp extends StatelessWidget {
  const CfAiUltimateApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: const MainTabScreen(),
  );
}

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});
  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [const IpScannerPage(), const AiReviewPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: '深度优选',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI评价',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. 页面一：深度优选 (含所有黄金节点与修正逻辑)
// ==========================================
class IpScannerPage extends StatefulWidget {
  const IpScannerPage({super.key});
  @override
  State<IpScannerPage> createState() => _IpScannerPageState();
}

class _IpScannerPageState extends State<IpScannerPage> {
  final List<IpResult> _results = [];
  bool _isScanning = false;
  double _progress = 0.0;
  String _statusMessage = '就绪：双栈战神库已加载';

  // 网段池
  final List<String> _cfIPv6Cidrs = [
    '2400:cb00::/32',
    '2405:b500::/32',
    '2405:8100::/32',
    '2a06:98c0::/29',
  ];
  final List<String> _cfIPv4Cidrs = [
    '162.158.0.0/15',
    '172.64.0.0/13',
    '104.16.0.0/13',
  ];

  // 你提供的静态黄金节点
  final List<String> _goldV6Nodes = [
    "2606:4700::1",
    "2606:4700::1111",
    "2606:4700:4700::1001",
    "2400:cb00:2048:1::c629:d7a2",
    "2400:cb00:2048:1::6814:d52d",
    "2606:4700:3033::ac43:a33a",
    "2606:4700:3037::6815:242e",
    "2a06:98c1:3121::3",
    "2405:b500:2048:1::6812:1db1",
    "2a06:98c1:3120::4c",
    "2400:cb00:2048:1::6814:d065",
    "2405:b500:2048:1::6812:1dae",
    "2606:4700:58::a29f:2c36",
    "2400:cb00:2048:1::ac43:1b0a",
  ];

  Future<void> _startDeepScan() async {
    setState(() {
      _isScanning = true;
      _results.clear();
      _progress = 0.0;
      _statusMessage = '正在唤醒 IPv6 协议栈...';
    });

    List<IpResult> pool = [];

    // 注入保底 IP (确认 App 是否通 IPv6)
    pool.add(IpResult(ip: "240c::6666", isIpv6: true));

    // A. 注入静态黄金节点
    for (var ip in _goldV6Nodes) {
      pool.add(IpResult(ip: ip, isIpv6: true));
    }

    // B. 亚洲网段步进挖掘
    for (var cidr in _cfIPv6Cidrs) {
      String prefix = cidr.split('::/')[0];
      for (int i = 1; i <= 25; i++) {
        pool.add(IpResult(ip: "$prefix:$i", isIpv6: true));
        pool.add(IpResult(ip: "$prefix:ad$i", isIpv6: true));
      }
    }

    // C. 补充 IPv4 采样
    for (var c in _cfIPv4Cidrs) {
      _generateIpv4(
        c,
        30,
      ).forEach((ip) => pool.add(IpResult(ip: ip, isIpv6: false)));
    }

    pool.shuffle();

    const int batchSize = 35;
    for (int i = 0; i < pool.length; i += batchSize) {
      if (!_isScanning) break;
      int end = (i + batchSize < pool.length) ? i + batchSize : pool.length;
      var batch = pool.sublist(i, end);

      setState(() => _statusMessage = '深度探测中: $i / ${pool.length}');
      await Future.wait(
        batch.map((item) async {
          item.latency = await _testLatency(item.ip, item.isIpv6);
        }),
      );

      setState(() {
        _results.addAll(batch.where((r) => r.latency < 2000));
        _results.sort((a, b) => a.latency.compareTo(b.latency));
        _progress = (i + batch.length) / pool.length;
      });
    }
    setState(() {
      _isScanning = false;
      _statusMessage = '扫描完成！';
    });
  }

  // 核心探测引擎：强制双栈握手
  Future<int> _testLatency(String ip, bool isIpv6) async {
    int total = 0, success = 0;
    for (int i = 0; i < 3; i++) {
      try {
        final sw = Stopwatch()..start();
        // 重要修正：显式指定 sourceAddress 强制系统启用对应的 IP 协议栈
        final socket = await Socket.connect(
          ip,
          443,
          timeout: Duration(milliseconds: isIpv6 ? 1200 : 800),
          sourceAddress: isIpv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
        );
        sw.stop();
        socket.destroy();
        success++;
        total += sw.elapsedMilliseconds;
        await Future.delayed(const Duration(milliseconds: 20));
      } catch (_) {}
    }
    return success < 1 ? 9999 : total ~/ success;
  }

  List<String> _generateIpv4(String cidr, int count) {
    List<String> parts = cidr.split('/');
    List<int> b = parts[0].split('.').map(int.parse).toList();
    int ipInt = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    int range = pow(2, 32 - int.parse(parts[1])).toInt();
    Random r = Random();
    return List.generate(count, (_) {
      int t = ipInt + r.nextInt(range);
      return [
        (t >> 24) & 0xFF,
        (t >> 16) & 0xFF,
        (t >> 8) & 0xFF,
        t & 0xFF,
      ].join('.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CF 深度优选 (双栈修正版)'), elevation: 2),
      body: Column(
        children: [
          if (_isScanning) LinearProgressIndicator(value: _progress),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: Colors.indigo.withOpacity(0.05),
            child: Text(
              '状态: $_statusMessage',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final r = _results[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    r.isIpv6 ? Icons.rocket_launch : Icons.lan,
                    color: r.isIpv6 ? Colors.orange : Colors.blue,
                    size: 20,
                  ),
                  title: Text(
                    r.ip,
                    style: TextStyle(
                      fontSize: r.isIpv6 ? 11 : 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: Text(
                    '${r.latency}ms',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: r.ip));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('IP 已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _startDeepScan,
              icon: const Icon(Icons.radar),
              label: const Text('开始深度优选'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. 页面二：AI 评价助手
// ==========================================
class AiReviewPage extends StatefulWidget {
  const AiReviewPage({super.key});
  @override
  State<AiReviewPage> createState() => _AiReviewPageState();
}

class _AiReviewPageState extends State<AiReviewPage> {
  final _prodCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  String _style = "热情";
  String _res = "";
  bool _loading = false;

  void _run() async {
    if (_prodCtrl.text.isEmpty) return;
    setState(() {
      _loading = true;
      _res = "";
    });
    final s = await ApiService.generateReview(
      product: _prodCtrl.text,
      tags: _tagCtrl.text,
      style: _style,
    );
    setState(() {
      _res = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 好评生成器')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _prodCtrl,
            decoration: const InputDecoration(
              labelText: "商品名称",
              border: OutlineInputBorder(),
              hintText: "例如：Redmi K70",
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _tagCtrl,
            decoration: const InputDecoration(
              labelText: "关键词",
              border: OutlineInputBorder(),
              hintText: "手感好, 运行流畅",
            ),
          ),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: _style,
            decoration: const InputDecoration(
              labelText: "文案风格",
              border: OutlineInputBorder(),
            ),
            items: [
              "热情",
              "简洁",
              "幽默",
              "专业",
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _style = v!),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loading ? null : _run,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: const Text("生成评价文案"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
          if (_res.isNotEmpty) ...[
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.05),
                border: Border.all(color: Colors.amber.shade200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_res, style: const TextStyle(height: 1.5)),
            ),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: _res)),
              icon: const Icon(Icons.copy),
              label: const Text("复制结果"),
            ),
          ],
        ],
      ),
    );
  }
}
