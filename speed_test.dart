import 'dart:io';

class CheckResult {
  final String ip;
  final int? latency; // 延迟（毫秒），null 表示不通
  CheckResult(this.ip, this.latency);
}

class CloudflareScanner {
  // 核心函数：测试单个 IP 的 TCP 握手延迟
  Future<CheckResult> testIp(String ip) async {
    final stopwatch = Stopwatch()..start();
    try {
      // 尝试建立连接，设置 1 秒超时
      final socket = await Socket.connect(ip, 443, timeout: Duration(milliseconds: 1000));
      stopwatch.stop();
      socket.destroy(); // 记得关闭连接
      return CheckResult(ip, stopwatch.elapsedMilliseconds);
    } catch (e) {
      return CheckResult(ip, null); // 连接失败
    }
  }
}

Future<List<CheckResult>> startScan(List<String> ipList) async {
  // 每次并发处理 20 个 IP，防止手机网络崩溃
  List<CheckResult> results = [];
  
  // 简单的分批处理逻辑
  for (var i = 0; i < ipList.length; i += 20) {
    var chunk = ipList.sublist(i, i + 20 > ipList.length ? ipList.length : i + 20);
    
    // 同时发起 20 个请求
    var batchResults = await Future.wait(chunk.map((ip) => testIp(ip)));
    results.addAll(batchResults);
  }
  
  // 过滤掉不通的，并按延迟从小到大排序
  results.removeWhere((element) => element.latency == null);
  results.sort((a, b) => a.latency!.compareTo(b.latency!));
  
  return results;
}