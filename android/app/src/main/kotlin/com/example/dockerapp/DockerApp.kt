package com.example.dockerapp

import android.app.Application

/**
 * Application singleton that holds VmManager so it survives Activity recreations.
 * Without this, each new MainActivity instance would create a fresh VmManager,
 * losing track of the running QEMU process and causing port 7080 contention on restart.
 */
class DockerApp : Application() {
    lateinit var vmManager: VmManager
        private set

    override fun onCreate() {
        super.onCreate()
        vmManager = VmManager(this)
    }
}
