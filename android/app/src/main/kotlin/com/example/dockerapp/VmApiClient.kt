package com.example.dockerapp

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class VmApiClient {
    private val TAG = "VmApiClient"
    private val baseUrl = "http://127.0.0.1:7080"
    private val gson = Gson()

    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    fun checkHealth(): Boolean {
        return try {
            val request = Request.Builder()
                .url("$baseUrl/health")
                .get()
                .build()

            val response = client.newCall(request).execute()
            val success = response.isSuccessful
            response.close()
            success
        } catch (e: Exception) {
            Log.e(TAG, "Health check failed", e)
            false
        }
    }

    fun startContainer(image: String, name: String, cmd: List<String>) {
        try {
            val json = JsonObject().apply {
                addProperty("image", image)
                addProperty("name", name)
                add("cmd", gson.toJsonTree(cmd))
            }

            val body = gson.toJson(json).toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("$baseUrl/containers/start")
                .post(body)
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                throw Exception("Failed to start container: ${response.code}")
            }
            response.close()
            Log.d(TAG, "Container started: $name")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting container", e)
            throw e
        }
    }

    fun stopContainer(name: String) {
        try {
            val json = JsonObject().apply {
                addProperty("name", name)
            }

            val body = gson.toJson(json).toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("$baseUrl/containers/stop")
                .post(body)
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                throw Exception("Failed to stop container: ${response.code}")
            }
            response.close()
            Log.d(TAG, "Container stopped: $name")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping container", e)
            throw e
        }
    }

    fun listContainers(): List<Map<String, Any>> {
        return try {
            val request = Request.Builder()
                .url("$baseUrl/containers")
                .get()
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                response.close()
                return emptyList()
            }

            val json = response.body?.string() ?: "[]"
            response.close()

            val list = gson.fromJson(json, List::class.java) as? List<Map<String, Any>> ?: emptyList()
            list
        } catch (e: Exception) {
            Log.e(TAG, "Error listing containers", e)
            emptyList()
        }
    }

    fun getLogs(name: String, tail: Int): String {
        return try {
            val request = Request.Builder()
                .url("$baseUrl/logs?name=$name&tail=$tail")
                .get()
                .build()

            val response = client.newCall(request).execute()
            val logs = if (response.isSuccessful) {
                response.body?.string() ?: ""
            } else {
                ""
            }
            response.close()
            logs
        } catch (e: Exception) {
            Log.e(TAG, "Error getting logs", e)
            ""
        }
    }
}
