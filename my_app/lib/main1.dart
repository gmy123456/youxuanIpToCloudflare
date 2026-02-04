import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';

void main() => runApp(const CfUltimateApp());

class IpResult {
  final String ip;
  int latency;
  final bool isIpv6;
  IpResult({required this.ip, this.latency = 9999, required this.isIpv6});
}

class CfUltimateApp extends StatelessWidget {
  const CfUltimateApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
    home: const ScannerScreen(),
  );
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final List<IpResult> _results = [];
  bool _isScanning = false;
  double _progress = 0.0;
  String _statusMessage = '全能模式：正在平衡双栈比例...';

  // IPv4 优化网段 (针对晚高峰优化的非 104 段)
  final List<String> _cfIPv4Cidrs = [
    '162.158.0.0/15',
    '172.64.0.0/13',
    '103.21.244.0/22',
  ];
  // IPv6 亚洲步进段
  final List<String> _cfIPv6Cidrs = [
    '2400:cb00::/32',
    '2405:b500::/32',
    '2a06:98c0::/29',
    '2400:cb00::/32',
    '2405:b500::/32',
    '2405:8100::/32',
    '2a06:98c0::/29',
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
    "2400:cb00:2048:1::6814:d065", // 往往指向香港
    "2405:b500:2048:1::6812:1dae", // 往往指向新加坡
    "2606:4700:58::a29f:2c36", // 备用亚洲路径
    "2400:cb00:2048:1::ac43:1b0a",
  ];

  Future<void> _startUltimateScan() async {
    setState(() {
      _isScanning = true;
      _results.clear();
      _progress = 0.0;
      _statusMessage = '正在调集双栈精兵强将...';
    });

    List<IpResult> pool = [];

    // 1. 生成 IPv6 步进采样 (取前 80 个)
    for (var cidr in _cfIPv6Cidrs) {
      String prefix = cidr.split('::/')[0];
      for (int i = 1; i <= 25; i++) {
        pool.add(IpResult(ip: "$prefix:$i", isIpv6: true));
        pool.add(IpResult(ip: "$prefix:ad$i", isIpv6: true));
      }
    }

    // 2. 生成 IPv4 随机采样 (取 80 个)
    for (var cidr in _cfIPv4Cidrs) {
      _generateIpv4(
        cidr,
        25,
      ).forEach((ip) => pool.add(IpResult(ip: ip, isIpv6: false)));
    }

    pool.shuffle();

    const int batchSize = 45;
    for (int i = 0; i < pool.length; i += batchSize) {
      if (!_isScanning) break;
      int end = (i + batchSize < pool.length) ? i + batchSize : pool.length;
      var batch = pool.sublist(i, end);

      setState(() => _statusMessage = '全速探测中: $i / ${pool.length}');

      await Future.wait(
        batch.map((item) async {
          item.latency = await _testLatency(item.ip, item.isIpv6);
        }),
      );

      setState(() {
        _results.addAll(batch.where((r) => r.latency < 1000));
        _results.sort((a, b) => a.latency.compareTo(b.latency));
        _progress = (i + batch.length) / pool.length;
      });
    }

    setState(() {
      _isScanning = false;
      _statusMessage = '扫描完成！已平衡 IPv4 与 IPv6 结果';
    });
  }

  Future<int> _testLatency(String ip, bool isIpv6) async {
    int total = 0, success = 0;
    for (int i = 0; i < 3; i++) {
      // 3 次探测取平均
      try {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(
          ip,
          443,
          timeout: const Duration(milliseconds: 700),
          sourceAddress: isIpv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
        );
        sw.stop();
        socket.destroy();
        success++;
        total += sw.elapsedMilliseconds;
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
      appBar: AppBar(
        title: const Text('CF 双栈全能优选'),
        backgroundColor: Colors.deepPurple.shade50,
      ),
      body: Column(
        children: [
          _buildStatus(),
          if (_isScanning) const LinearProgressIndicator(),
          Expanded(child: _buildList()),
          _buildActionBtn(),
        ],
      ),
    );
  }

  Widget _buildStatus() => Container(
    padding: const EdgeInsets.all(12),
    width: double.infinity,
    color: Colors.deepPurple.withOpacity(0.05),
    child: Text('状态: $_statusMessage', style: const TextStyle(fontSize: 12)),
  );

  Widget _buildList() {
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        bool isV6 = r.isIpv6;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isV6
                ? Colors.blue.shade100
                : Colors.orange.shade100,
            child: Text(
              isV6 ? 'V6' : 'V4',
              style: TextStyle(
                fontSize: 10,
                color: isV6 ? Colors.blue : Colors.orange,
              ),
            ),
          ),
          title: Text(
            r.ip,
            style: TextStyle(fontSize: isV6 ? 11 : 14, fontFamily: 'monospace'),
          ),
          trailing: Text(
            '${r.latency}ms',
            style: TextStyle(
              color: r.latency < 160 ? Colors.green : Colors.blueGrey,
              fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildActionBtn() => Padding(
    padding: const EdgeInsets.all(20),
    child: ElevatedButton.icon(
      onPressed: _isScanning ? null : _startUltimateScan,
      icon: const Icon(Icons.flash_on),
      label: const Text('开始全能双栈扫描'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    ),
  );
}
