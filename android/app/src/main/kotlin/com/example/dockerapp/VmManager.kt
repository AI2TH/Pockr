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
    private val vmDir: File get() = File(filesDir, "vm")
    private val bootstrapDir: File get() = File(filesDir, "bootstrap")

    // QEMU binaries are installed by Android into nativeLibraryDir as .so files.
    // This directory is SELinux-labelled exec_type — safe to execute on Android 10+.
    // libqemu.so      = qemu-system-aarch64
    // libqemu_img.so  = qemu-img
    private val nativeLibDir: File
        get() = File(context.applicationInfo.nativeLibraryDir)

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
        Log.d(TAG, "QEMU binary: ${qemuBin.absolutePath}")

        // Flutter SharedPreferences stores ints as Long on Android — handle both types
        val vcpu = getFlutterInt("flutter.vcpu_count", 2)
        val ramMb = getFlutterInt("flutter.ram_mb", 2048)

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
            // Add nativeLibDir to LD_LIBRARY_PATH for any shared libs QEMU needs
            environment()["LD_LIBRARY_PATH"] = nativeLibDir.absolutePath
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
        vmProcess?.let {
            try {
                it.exitValue()
                Log.w(TAG, "QEMU process exited unexpectedly")
                isRunning = false
                return false
            } catch (_: IllegalThreadStateException) { }
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

    // Flutter SharedPreferences stores integers as Long on Android (not Int).
    // Use this helper to safely read either type.
    private fun getFlutterInt(key: String, default: Int): Int {
        return try {
            flutterPrefs.getInt(key, default)
        } catch (_: ClassCastException) {
            flutterPrefs.getLong(key, default.toLong()).toInt()
        }
    }

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
    // Asset extraction (vm images + bootstrap scripts only)
    // QEMU binaries are handled by Android via jniLibs — no manual extraction
    // -------------------------------------------------------------------------

    private fun assetsReady(): Boolean {
        val marker = File(filesDir, "assets_extracted.v2")
        return marker.exists()
            && resolveQemuBinary().exists()
            && File(vmDir, "base.qcow2").exists()
    }

    private fun extractAssets() {
        vmDir.mkdirs()
        bootstrapDir.mkdirs()

        // Base image — aapt2 decompresses .gz assets and drops the extension.
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

        File(filesDir, "assets_extracted.v2").createNewFile()
        Log.d(TAG, "Assets extracted to $filesDir")
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
    // QCOW2 user image creation via qemu-img (from nativeLibraryDir)
    // -------------------------------------------------------------------------

    private fun createUserImage(userImagePath: String, baseImagePath: String) {
        val qemuImg = File(nativeLibDir, "libqemu_img.so")
        if (!qemuImg.exists()) {
            throw IllegalStateException(
                "libqemu_img.so not found in nativeLibraryDir: ${nativeLibDir.absolutePath}"
            )
        }

        val proc = ProcessBuilder(
            qemuImg.absolutePath, "create",
            "-f", "qcow2",
            "-b", baseImagePath,
            "-F", "qcow2",
            userImagePath,
            "8G"
        ).apply {
            environment()["LD_LIBRARY_PATH"] = nativeLibDir.absolutePath
        }.start()

        val exitCode = proc.waitFor()
        if (exitCode != 0) {
            val err = proc.errorStream.bufferedReader().readText()
            throw RuntimeException("qemu-img create failed (exit $exitCode): $err")
        }
        Log.d(TAG, "Created user.qcow2 at $userImagePath")
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

        cmd += listOf("-drive", "if=none,file=$baseImage,id=base,format=qcow2,readonly=on")
        cmd += listOf("-drive", "if=none,file=$userImage,id=user,format=qcow2")
        cmd += listOf("-device", "virtio-blk-pci,drive=user")

        cmd += listOf("-netdev", "user,id=net0,hostfwd=tcp::7080-:7080")
        cmd += listOf("-device", "virtio-net-pci,netdev=net0")

        cmd += listOf("-fw_cfg", "name=opt/api_token,string=$token")
        cmd += listOf("-display", "none")

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

    private fun resolveQemuBinary(): File {
        // QEMU is installed by Android's PackageManager into nativeLibraryDir as libqemu.so
        val bin = File(nativeLibDir, "libqemu.so")
        if (!bin.exists()) {
            throw IllegalStateException(
                "libqemu.so not found in nativeLibraryDir: ${nativeLibDir.absolutePath}. " +
                "Ensure jniLibs/arm64-v8a/libqemu.so is present in the project."
            )
        }
        return bin
    }
}
