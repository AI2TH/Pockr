package com.example.dockerapp

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.dockerapp/vm"
    private lateinit var vmManager: VmManager
    private val executor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        vmManager = VmManager(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Heavy ops run on background thread; result posted back on main thread
                    "startVm" -> executor.execute {
                        try {
                            startVmService()
                            vmManager.startVm()
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("VM_START_ERROR", e.message, null) }
                        }
                    }

                    "stopVm" -> executor.execute {
                        try {
                            vmManager.stopVm()
                            stopVmService()
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("VM_STOP_ERROR", e.message, null) }
                        }
                    }

                    "checkHealth" -> executor.execute {
                        try {
                            val healthy = vmManager.checkHealth()
                            runOnUiThread { result.success(healthy) }
                        } catch (e: Exception) {
                            runOnUiThread { result.success(false) }
                        }
                    }

                    "getVmStatus" -> {
                        // Lightweight — no I/O, safe on main thread
                        try {
                            result.success(vmManager.getStatus())
                        } catch (e: Exception) {
                            result.success("unknown")
                        }
                    }

                    "startContainer" -> executor.execute {
                        try {
                            val image = call.argument<String>("image")
                                ?: return@execute runOnUiThread {
                                    result.error("CONTAINER_START_ERROR", "image required", null)
                                }
                            val name = call.argument<String>("name")
                                ?: return@execute runOnUiThread {
                                    result.error("CONTAINER_START_ERROR", "name required", null)
                                }
                            val cmd = call.argument<List<String>>("cmd") ?: emptyList()
                            vmManager.startContainer(image, name, cmd)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("CONTAINER_START_ERROR", e.message, null) }
                        }
                    }

                    "stopContainer" -> executor.execute {
                        try {
                            val name = call.argument<String>("name")
                                ?: return@execute runOnUiThread {
                                    result.error("CONTAINER_STOP_ERROR", "name required", null)
                                }
                            vmManager.stopContainer(name)
                            runOnUiThread { result.success(null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("CONTAINER_STOP_ERROR", e.message, null) }
                        }
                    }

                    "listContainers" -> executor.execute {
                        try {
                            val containers = vmManager.listContainers()
                            runOnUiThread { result.success(containers) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("CONTAINER_LIST_ERROR", e.message, null) }
                        }
                    }

                    "getLogs" -> executor.execute {
                        try {
                            val name = call.argument<String>("name")
                                ?: return@execute runOnUiThread {
                                    result.error("LOGS_ERROR", "name required", null)
                                }
                            val tail = call.argument<Int>("tail") ?: 100
                            val logs = vmManager.getLogs(name, tail)
                            runOnUiThread { result.success(logs) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("LOGS_ERROR", e.message, null) }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
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
