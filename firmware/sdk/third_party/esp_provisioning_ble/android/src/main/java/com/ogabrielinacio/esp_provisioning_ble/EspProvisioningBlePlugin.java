package com.ogabrielinacio.esp_provisioning_ble;

import androidx.annotation.NonNull;

import java.security.GeneralSecurityException;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Android AES-CTR bridge used by Security 1 provisioning. */
public final class EspProvisioningBlePlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Cipher cipher;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "esp_provisioning_ble");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "getPlatformVersion":
                result.success("Android " + android.os.Build.VERSION.RELEASE);
                return;
            case "init":
                initializeCipher(call, result);
                return;
            case "crypt":
                crypt(call, result);
                return;
            default:
                result.notImplemented();
        }
    }

    private void initializeCipher(MethodCall call, MethodChannel.Result result) {
        final byte[] key = call.argument("key");
        final byte[] iv = call.argument("iv");
        if (key == null || iv == null) {
            result.error("invalid_arguments", "AES key and IV are required.", null);
            return;
        }
        try {
            cipher = Cipher.getInstance("AES/CTR/NoPadding");
            cipher.init(
                    Cipher.ENCRYPT_MODE,
                    new SecretKeySpec(key, "AES"),
                    new IvParameterSpec(iv));
            result.success(true);
        } catch (GeneralSecurityException error) {
            result.error("crypto_init", error.getMessage(), null);
        }
    }

    private void crypt(MethodCall call, MethodChannel.Result result) {
        final byte[] data = call.argument("data");
        if (cipher == null || data == null) {
            result.error(
                    "crypto_uninitialized",
                    "Initialize AES before encrypting data.",
                    null);
            return;
        }
        result.success(cipher.update(data));
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
        cipher = null;
    }
}
