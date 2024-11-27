package moe.yashi.nfc_ftm_example;

import android.content.Intent;
import android.os.Bundle;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugins.GeneratedPluginRegistrant;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    // private static final String CHANNEL = "moe.yashi.nfc_ftm_example/nfc";
    // private NfcAdapter nfcAdapter;

    // @Override
    // protected void onCreate(Bundle savedInstanceState) {
    //     super.onCreate(savedInstanceState);
    //     // 初始化 NFC
    //     nfcAdapter = NfcAdapter.getDefaultAdapter(this);
    //     if (nfcAdapter == null) {
    //         // 设备不支持 NFC
    //         return;
    //     }
    // }

    // @Override
    // protected void onResume() {
    //     super.onResume();
    //     // 检查当前 Intent 是否是 NFC 标签扫描事件
    //     if (NfcAdapter.ACTION_TAG_DISCOVERED.equals(getIntent().getAction())) {
    //         // 获取 NFC 标签
    //         Tag tag = getIntent().getParcelableExtra(NfcAdapter.EXTRA_TAG);
    //         if (tag != null) {
    //             // 传递 NFC 标签数据给 Flutter
    //             sendNfcDataToFlutter(tag);
    //         }
    //     }
    // }

    // @Override
    // protected void onNewIntent(Intent intent) {
    //     super.onNewIntent(intent);
    //     setIntent(intent); // 更新当前的 intent
    // }

    // // 通过 MethodChannel 将 NFC 标签数据传递给 Flutter
    // private void sendNfcDataToFlutter(Tag tag) {
    //     String tagId = new String(tag.getId());
    //     // 获取 FlutterEngine 并通过 MethodChannel 传递 NFC 数据
    //     MethodChannel channel = new MethodChannel(getFlutterEngine().getDartExecutor(), CHANNEL);
    //     channel.invokeMethod("onNfcScanned", tagId);
    // }

    // @Override
    // public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    //     super.configureFlutterEngine(flutterEngine);
    //     // 注册插件
    //     GeneratedPluginRegistrant.registerWith(flutterEngine);
    // }
}