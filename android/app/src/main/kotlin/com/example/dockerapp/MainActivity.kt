package com.example.dockerapp

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.dockerapp/vm"
    private lateinit var vmManager: VmManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        vmManager = VmManager(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVm" -> {
                    try {
                        startVmService()
                        vmManager.startVm()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("VM_START_ERROR", e.message, null)
                    }
                }
                "stopVm" -> {
                    try {
                        vmManager.stopVm()
                        stopVmService()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("VM_STOP_ERROR", e.message, null)
                    }
                }
                "checkHealth" -> {
                    try {
                        val healthy = vmManager.checkHealth()
                        result.success(healthy)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getVmStatus" -> {
                    try {
                        val status = vmManager.getStatus()
                        result.success(status)
                    } catch (e: Exception) {
                        result.success("unknown")
                    }
                }
                "startContainer" -> {
                    try {
                        val image = call.argument<String>("image") ?: throw IllegalArgumentException("image required")
                        val name = call.argument<String>("name") ?: throw IllegalArgumentException("name required")
                        val cmd = call.argument<List<String>>("cmd") ?: emptyList()
                        vmManager.startContainer(image, name, cmd)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CONTAINER_START_ERROR", e.message, null)
                    }
                }
                "stopContainer" -> {
                    try {
                        val name = call.argument<String>("name") ?: throw IllegalArgumentException("name required")
                        vmManager.stopContainer(name)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CONTAINER_STOP_ERROR", e.message, null)
                    }
                }
                "listContainers" -> {
                    try {
                        val containers = vmManager.listContainers()
                        result.success(containers)
                    } catch (e: Exception) {
                        result.error("CONTAINER_LIST_ERROR", e.message, null)
                    }
                }
                "getLogs" -> {
                    try {
                        val name = call.argument<String>("name") ?: throw IllegalArgumentException("name required")
                        val tail = call.argument<Int>("tail") ?: 100
                        val logs = vmManager.getLogs(name, tail)
                        result.success(logs)
                    } catch (e: Exception) {
                        result.error("LOGS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVmService() {
        val intent = Intent(this, VmService::class.java)
        startForegroundService(intent)
    }

    private fun stopVmService() {
        val intent = Intent(this, VmService::class.java)
        stopService(intent)
    }
}
