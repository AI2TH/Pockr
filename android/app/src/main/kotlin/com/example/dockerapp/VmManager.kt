package com.example.dockerapp

import android.content.Context
import android.util.Log
import java.io.File

class VmManager(private val context: Context) {
    private val TAG = "VmManager"
    private var vmProcess: Process? = null
    private var isRunning = false

    private val filesDir: File
        get() = context.filesDir

    private val qemuDir: File
        get() = File(filesDir, "qemu")

    private val vmDir: File
        get() = File(filesDir, "vm")

    private val apiClient = VmApiClient()

    fun startVm() {
        Log.d(TAG, "Starting VM...")

        // Check if assets are extracted
        if (!qemuDir.exists() || !vmDir.exists()) {
            Log.d(TAG, "Assets not extracted, extracting now...")
            extractAssets()
        }

        // TODO: Launch QEMU process
        // For now, just mark as running
        isRunning = true
        Log.d(TAG, "VM start initiated (stub implementation)")
    }

    fun stopVm() {
        Log.d(TAG, "Stopping VM...")
        vmProcess?.destroy()
        vmProcess = null
        isRunning = false
        Log.d(TAG, "VM stopped")
    }

    fun checkHealth(): Boolean {
        if (!isRunning) return false
        return apiClient.checkHealth()
    }

    fun getStatus(): String {
        return when {
            vmProcess != null && isRunning -> "running"
            else -> "stopped"
        }
    }

    fun startContainer(image: String, name: String, cmd: List<String>) {
        Log.d(TAG, "Starting container: $name from $image")
        apiClient.startContainer(image, name, cmd)
    }

    fun stopContainer(name: String) {
        Log.d(TAG, "Stopping container: $name")
        apiClient.stopContainer(name)
    }

    fun listContainers(): List<Map<String, Any>> {
        return apiClient.listContainers()
    }

    fun getLogs(name: String, tail: Int): String {
        return apiClient.getLogs(name, tail)
    }

    private fun extractAssets() {
        Log.d(TAG, "Extracting assets...")

        // Create directories
        qemuDir.mkdirs()
        vmDir.mkdirs()

        // TODO: Extract QEMU binaries from assets
        // TODO: Extract base.qcow2.gz from assets
        // TODO: Decompress base.qcow2
        // TODO: Create user.qcow2 overlay

        Log.d(TAG, "Assets extracted (stub implementation)")
    }
}
