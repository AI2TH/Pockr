package com.example.dockerapp

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.zip.GZIPInputStream

class VmManager(private val context: Context) {
    private val TAG = "VmManager"
    private var vmProcess: Process? = null
    private var isRunning = false

    private val filesDir: File get() = context.filesDir
    private val qemuDir: File get() = File(filesDir, "qemu")
    private val vmDir: File get() = File(filesDir, "vm")
    private val bootstrapDir: File get() = File(filesDir, "bootstrap")

    // Flutter SharedPreferences stores keys with "flutter." prefix
    private val flutterPrefs: SharedPreferences
        get() = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    // App-private prefs for internal state (token, extraction version)
    private val appPrefs: SharedPreferences
        get() = context.getSharedPreferences("vm_app_prefs", Context.MODE_PRIVATE)

    private val token: String by lazy { getOrCreateToken() }

    val apiClient: VmApiClient by lazy { VmApiClient(token) }

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    fun startVm() {
        Log.d(TAG, "Starting VM...")

        if (!assetsReady()) {
            Log.d(TAG, "Assets not ready, extracting...")
            extractAssets()
        }

        val qemuBin = resolveQemuBinary()
        qemuBin.setExecutable(true, true)

        val vcpu = flutterPrefs.getInt("flutter.vcpu_count", 2)
        val ramMb = flutterPrefs.getInt("flutter.ram_mb", 2048)

        val baseImage = File(vmDir, "base.qcow2")
        val userImage = File(vmDir, "user.qcow2")
        if (!userImage.exists()) {
            createUserImage(userImage.absolutePath, baseImage.absolutePath)
        }

        val cmd = buildQemuCommand(
            qemuBin = qemuBin.absolutePath,
            baseImage = baseImage.absolutePath,
            userImage = userImage.absolutePath,
            vcpu = vcpu,
            ramMb = ramMb
        )

        Log.d(TAG, "QEMU command: ${cmd.joinToString(" ")}")

        vmProcess = ProcessBuilder(cmd).apply {
            // Add qemuDir to LD_LIBRARY_PATH so QEMU can find bundled shared libs
            environment()["LD_LIBRARY_PATH"] = qemuDir.absolutePath
            redirectErrorStream(true)
        }.start()

        isRunning = true

        // Drain QEMU stdout/stderr in background to prevent pipe buffer deadlock
        Thread {
            try {
                vmProcess?.inputStream?.bufferedReader()?.forEachLine { line ->
                    Log.d("QEMU", line)
                }
            } catch (e: Exception) {
                Log.w(TAG, "QEMU output reader closed: ${e.message}")
            }
        }.apply { isDaemon = true; start() }

        Log.d(TAG, "VM process launched")
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
        // Also verify the process hasn't exited unexpectedly
        vmProcess?.let {
            try {
                it.exitValue()
                // exitValue() returns without throwing = process has exited
                Log.w(TAG, "QEMU process exited unexpectedly")
                isRunning = false
                return false
            } catch (_: IllegalThreadStateException) {
                // Still running — expected
            }
        }
        return apiClient.checkHealth()
    }

    fun getStatus(): String {
        if (!isRunning) return "stopped"
        vmProcess?.let {
            return try {
                it.exitValue()
                isRunning = false
                "stopped"
            } catch (_: IllegalThreadStateException) {
                "running"
            }
        }
        return "stopped"
    }

    fun startContainer(image: String, name: String, cmd: List<String>) =
        apiClient.startContainer(image, name, cmd)

    fun stopContainer(name: String) = apiClient.stopContainer(name)

    fun listContainers(): List<Map<String, Any>> = apiClient.listContainers()

    fun getLogs(name: String, tail: Int): String = apiClient.getLogs(name, tail)

    // -------------------------------------------------------------------------
    // Token management
    // -------------------------------------------------------------------------

    private fun getOrCreateToken(): String {
        var t = appPrefs.getString("api_token", null)
        if (t == null) {
            t = UUID.randomUUID().toString()
            appPrefs.edit().putString("api_token", t).apply()
            Log.d(TAG, "Generated new API token")
        }
        return t
    }

    // -------------------------------------------------------------------------
    // Asset extraction
    // -------------------------------------------------------------------------

    private fun assetsReady(): Boolean {
        val marker = File(filesDir, "assets_extracted.v1")
        return marker.exists()
            && File(qemuDir, qemuBinaryName()).exists()
            && File(vmDir, "base.qcow2").exists()
    }

    private fun extractAssets() {
        qemuDir.mkdirs()
        vmDir.mkdirs()
        bootstrapDir.mkdirs()

        // QEMU main binary
        extractAsset("qemu/${qemuBinaryName()}", File(qemuDir, qemuBinaryName()))

        // Optional supporting binaries
        listOf("qemu-img").forEach { bin ->
            runCatching { extractAsset("qemu/$bin", File(qemuDir, bin)) }
                .onFailure { Log.w(TAG, "Optional asset qemu/$bin not found") }
        }

        // Optional ARM firmware
        if (isArm64()) {
            runCatching { extractAsset("qemu/efi.fd", File(qemuDir, "efi.fd")) }
                .onFailure { Log.w(TAG, "efi.fd not found — will skip UEFI firmware") }
        }

        // Base image — aapt2 may auto-decompress .gz assets and drop the extension.
        // Try the already-decompressed path first, fall back to .gz.
        val baseQcow2 = File(vmDir, "base.qcow2")
        if (!baseQcow2.exists()) {
            try {
                extractAsset("vm/base.qcow2", baseQcow2)
                Log.d(TAG, "Extracted base.qcow2 (aapt2 pre-decompressed)")
            } catch (_: Exception) {
                extractAndDecompress("vm/base.qcow2.gz", baseQcow2)
                Log.d(TAG, "Extracted + decompressed base.qcow2.gz")
            }
        }

        // Bootstrap scripts
        listOf("api_server.py", "requirements.txt", "init_bootstrap.sh").forEach { name ->
            runCatching { extractAsset("bootstrap/$name", File(bootstrapDir, name)) }
                .onFailure { Log.w(TAG, "Bootstrap asset $name not found") }
        }

        // Mark extraction version so we skip on subsequent launches
        File(filesDir, "assets_extracted.v1").createNewFile()
        Log.d(TAG, "Assets extracted successfully to $filesDir")
    }

    private fun extractAsset(assetPath: String, dest: File) {
        context.assets.open(assetPath).use { input ->
            FileOutputStream(dest).use { input.copyTo(it) }
        }
        Log.d(TAG, "Extracted $assetPath → ${dest.absolutePath}")
    }

    private fun extractAndDecompress(assetPath: String, dest: File) {
        context.assets.open(assetPath).use { raw ->
            GZIPInputStream(raw).use { gz ->
                FileOutputStream(dest).use { gz.copyTo(it) }
            }
        }
        Log.d(TAG, "Decompressed $assetPath → ${dest.absolutePath}")
    }

    // -------------------------------------------------------------------------
    // QCOW2 user image creation
    // -------------------------------------------------------------------------

    private fun createUserImage(userImagePath: String, baseImagePath: String) {
        val qemuImg = File(qemuDir, "qemu-img")
        if (!qemuImg.exists()) {
            // Without qemu-img we can't create a proper QCOW2 overlay; fail clearly
            throw IllegalStateException(
                "qemu-img not found at ${qemuImg.absolutePath}. " +
                "Ensure it is bundled in android/app/src/main/assets/qemu/qemu-img."
            )
        }

        qemuImg.setExecutable(true, true)

        val proc = ProcessBuilder(
            qemuImg.absolutePath, "create",
            "-f", "qcow2",
            "-b", baseImagePath,
            "-F", "qcow2",
            userImagePath,
            "8G"
        ).apply {
            environment()["LD_LIBRARY_PATH"] = qemuDir.absolutePath
        }.start()

        val exitCode = proc.waitFor()
        if (exitCode != 0) {
            val err = proc.errorStream.bufferedReader().readText()
            throw RuntimeException("qemu-img create failed (exit $exitCode): $err")
        }
        Log.d(TAG, "Created user.qcow2 overlay at $userImagePath")
    }

    // -------------------------------------------------------------------------
    // QEMU launch command
    // -------------------------------------------------------------------------

    private fun buildQemuCommand(
        qemuBin: String,
        baseImage: String,
        userImage: String,
        vcpu: Int,
        ramMb: Int
    ): List<String> {
        val cmd = mutableListOf<String>()

        cmd += qemuBin

        if (isArm64()) {
            cmd += listOf("-machine", "virt")
            cmd += listOf("-cpu", "cortex-a53")
        } else {
            cmd += listOf("-machine", "q35")
            cmd += listOf("-cpu", "qemu64")
        }

        cmd += listOf("-smp", vcpu.toString())
        cmd += listOf("-m", ramMb.toString())

        // Read-only base image
        cmd += listOf("-drive", "if=none,file=$baseImage,id=base,format=qcow2,readonly=on")
        // Writable user overlay
        cmd += listOf("-drive", "if=none,file=$userImage,id=user,format=qcow2")
        cmd += listOf("-device", "virtio-blk-pci,drive=user")

        // User-mode networking with hostfwd for API port
        cmd += listOf("-netdev", "user,id=net0,hostfwd=tcp::7080-:7080")
        cmd += listOf("-device", "virtio-net-pci,netdev=net0")

        // Inject auth token into guest via fw_cfg
        // Guest reads: /sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw
        cmd += listOf("-fw_cfg", "name=opt/api_token,string=$token")

        cmd += listOf("-display", "none")

        // ARM64 UEFI firmware — optional; skip if not bundled
        if (isArm64()) {
            val efi = File(qemuDir, "efi.fd")
            if (efi.exists()) {
                cmd += listOf("-bios", efi.absolutePath)
            }
        }

        // Direct kernel boot (preferred — avoids UEFI dependency)
        // Assets: vm/vmlinuz-virt and vm/initramfs-virt extracted from Alpine ISO
        val kernel = File(vmDir, "vmlinuz-virt")
        val initrd = File(vmDir, "initramfs-virt")
        if (kernel.exists() && initrd.exists()) {
            cmd += listOf("-kernel", kernel.absolutePath)
            cmd += listOf("-initrd", initrd.absolutePath)
            cmd += listOf("-append", "console=ttyAMA0 root=/dev/vda rw quiet")
        }

        return cmd
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun isArm64(): Boolean =
        Build.SUPPORTED_ABIS.any { it.startsWith("arm64") }

    private fun qemuBinaryName(): String =
        if (isArm64()) "qemu-system-aarch64" else "qemu-system-x86_64"

    private fun resolveQemuBinary(): File {
        val bin = File(qemuDir, qemuBinaryName())
        if (!bin.exists()) {
            throw IllegalStateException(
                "QEMU binary not found at ${bin.absolutePath}. " +
                "Run scripts/extract_from_termux.sh or scripts/download_alpine.sh first."
            )
        }
        return bin
    }
}
