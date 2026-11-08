package dev.personal.englishlearning

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** No plaintext fallback; only ciphertext in noBackupFilesDir, key stays in Keystore. */
class NotionCredentialStore(private val context: Context) {
    companion object {
        const val SOURCE = "157d89e5-71fb-4e68-9640-1b04dbb1e627"
        private const val AAD = "EnglishLearning.Notion.ReadOnly.Android.v1"
    }
    private fun suffix(namespace: String?): String {
        if (namespace == null) return "readonly"
        require(context.packageName.endsWith(".acceptance") &&
            (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0 &&
            namespace.matches(Regex("[A-Za-z0-9_-]{1,48}")))
        return "test_$namespace"
    }
    private fun alias(suffix: String) = "$AAD.$suffix"
    private fun file(suffix: String) = AtomicFile(File(context.noBackupFilesDir, "notion_$suffix.enc"))
    private fun key(suffix: String, create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias(suffix), null) as? SecretKey)?.let { return it }
        check(create) // A missing/inaccessible key never silently resets encrypted data.
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias(suffix),
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }
    private fun validate(value: String) {
        require(value.toByteArray(Charsets.UTF_8).size <= 8192)
        val json = JSONObject(value)
        require(json.getString("data_source_id") == SOURCE)
        require(json.getString("token").matches(Regex("[\\x21-\\x7e]{20,2000}")))
    }
    fun write(value: String, namespace: String?) {
        validate(value)
        val id = suffix(namespace)
        val plain = value.toByteArray(Charsets.UTF_8)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key(id, true))
            cipher.updateAAD("$AAD.$id".toByteArray(Charsets.UTF_8))
            val encrypted = cipher.doFinal(plain)
            val payload = JSONObject().put("version", 1)
                .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .put("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .toString().toByteArray(Charsets.UTF_8)
            val target = file(id)
            val stream = target.startWrite()
            try { stream.write(payload); target.finishWrite(stream) }
            catch (e: Exception) { target.failWrite(stream); throw e }
        } finally { plain.fill(0) }
    }
    fun read(namespace: String?): String? {
        val id = suffix(namespace)
        val target = file(id)
        val content = try { target.openRead().use { input ->
            val data = input.readBytes(); require(data.size <= 16384); data
        } } catch (e: java.io.FileNotFoundException) { return null }
        val json = JSONObject(String(content, Charsets.UTF_8))
        require(json.getInt("version") == 1)
        val iv = Base64.decode(json.getString("iv"), Base64.NO_WRAP)
        require(iv.size == 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(id, false), GCMParameterSpec(128, iv))
        cipher.updateAAD("$AAD.$id".toByteArray(Charsets.UTF_8))
        val plain = cipher.doFinal(Base64.decode(json.getString("ciphertext"), Base64.NO_WRAP))
        try { return String(plain, Charsets.UTF_8).also { validate(it) } }
        finally { plain.fill(0) }
    }
    fun delete(namespace: String?) {
        val id = suffix(namespace)
        file(id).delete()
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(alias(id))) store.deleteEntry(alias(id))
    }
    fun inspectTest(namespace: String?, probe: String): Map<String, Any> {
        require(namespace != null)
        val id = suffix(namespace)
        val content = file(id).openRead().use { String(it.readBytes(), Charsets.UTF_8) }
        val secret = key(id, false)
        return mapOf("ciphertext_exists" to true,
            "plaintext_absent" to !content.contains(probe),
            "key_non_exportable" to (secret.encoded == null),
            "no_backup_directory" to true)
    }
    fun corruptTest(namespace: String?) {
        require(namespace != null)
        val id = suffix(namespace)
        val target = file(id)
        val data = target.openRead().use { JSONObject(String(it.readBytes(), Charsets.UTF_8)) }
        val cipher = Base64.decode(data.getString("ciphertext"), Base64.NO_WRAP)
        cipher[cipher.lastIndex] = (cipher.last().toInt() xor 1).toByte()
        data.put("ciphertext", Base64.encodeToString(cipher, Base64.NO_WRAP))
        val stream = target.startWrite()
        try { stream.write(data.toString().toByteArray(Charsets.UTF_8)); target.finishWrite(stream) }
        catch (e: Exception) { target.failWrite(stream); throw e }
    }
}
