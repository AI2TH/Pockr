import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VmPlatform {
  static const platform = MethodChannel('com.example.dockerapp/vm');

  static Future<void> startVm() async {
    try {
      await platform.invokeMethod('startVm');
    } on PlatformException catch (e) {
      debugPrint("Failed to start VM: ${e.message}");
      rethrow;
    }
  }

  static Future<void> stopVm() async {
    try {
      await platform.invokeMethod('stopVm');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop VM: ${e.message}");
      rethrow;
    }
  }

  static Future<bool> checkHealth() async {
    try {
      final bool result = await platform.invokeMethod('checkHealth');
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to check health: ${e.message}");
      return false;
    }
  }

  static Future<String> getVmStatus() async {
    try {
      final String result = await platform.invokeMethod('getVmStatus');
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to get VM status: ${e.message}");
      return 'unknown';
    }
  }

  static Future<void> startContainer(
      String image, String name, List<String> cmd) async {
    try {
      await platform.invokeMethod('startContainer', {
        'image': image,
        'name': name,
        'cmd': cmd,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to start container: ${e.message}");
      rethrow;
    }
  }

  static Future<void> stopContainer(String name) async {
    try {
      await platform.invokeMethod('stopContainer', {'name': name});
    } on PlatformException catch (e) {
      debugPrint("Failed to stop container: ${e.message}");
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> listContainers() async {
    try {
      final List<dynamic> result = await platform.invokeMethod('listContainers');
      return result.cast<Map<String, dynamic>>();
    } on PlatformException catch (e) {
      debugPrint("Failed to list containers: ${e.message}");
      return [];
    }
  }

  static Future<String> getLogs(String name, int tail) async {
    try {
      final String result = await platform.invokeMethod('getLogs', {
        'name': name,
        'tail': tail,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to get logs: ${e.message}");
      return '';
    }
  }
}

class VmState extends ChangeNotifier {
  String _status = 'stopped';
  bool _isHealthy = false;
  bool _isLoading = false;

  String get status => _status;
  bool get isHealthy => _isHealthy;
  bool get isLoading => _isLoading;

  Future<void> startVm() async {
    _isLoading = true;
    _status = 'starting';
    notifyListeners();

    try {
      await VmPlatform.startVm();
      _status = 'running';
      await Future.delayed(const Duration(seconds: 2));
      await checkHealth();
    } catch (e) {
      _status = 'error';
      debugPrint("Error starting VM: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> stopVm() async {
    _isLoading = true;
    notifyListeners();

    try {
      await VmPlatform.stopVm();
      _status = 'stopped';
      _isHealthy = false;
    } catch (e) {
      debugPrint("Error stopping VM: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> checkHealth() async {
    try {
      _isHealthy = await VmPlatform.checkHealth();
      if (_isHealthy && _status == 'starting') {
        _status = 'running';
      }
      notifyListeners();
    } catch (e) {
      _isHealthy = false;
      debugPrint("Error checking health: $e");
    }
  }

  Future<void> refreshStatus() async {
    try {
      _status = await VmPlatform.getVmStatus();
      if (_status == 'running') {
        await checkHealth();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error refreshing status: $e");
    }
  }
}
