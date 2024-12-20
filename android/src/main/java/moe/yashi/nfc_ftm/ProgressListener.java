package moe.yashi.nfc_ftm;


import com.st.st25sdk.ftmprotocol.FtmProtocol;

import android.os.Handler;
import android.os.Looper;

public class ProgressListener implements FtmProtocol.TransferProgressionListener {
    private final String TAG = "ProgressListener";
    private NfcFtmPlugin ftmP;

    // 定义一个 Handler 用于在主线程中执行任务
    private Handler mainHandler;

    public ProgressListener(NfcFtmPlugin nfcFtmP) {
        ftmP = nfcFtmP;
        mainHandler = new Handler(Looper.getMainLooper());
    }

    @Override
    public void transmissionProgress(int transmittedBytes, int acknowledgedBytes, int totalSize) {
        sendProgressData(true, transmittedBytes, acknowledgedBytes, totalSize);
    }

    @Override
    public void receptionProgress(int receivedBytes, int acknowledgedBytes, int totalSize) {
        sendProgressData(false, receivedBytes, acknowledgedBytes, totalSize);
    }

    // 计算并发送进度数据到主线程
    private void sendProgressData(boolean isTransmitted, int tORrBytes, int acknowledgedBytes, int totalSize) {
        mainHandler.post(new Runnable() {
            @Override
            public void run() {
                // 在主线程中处理进度数据，发送给 Flutter
                ftmP.updateProgress(isTransmitted, tORrBytes, acknowledgedBytes, totalSize);
            }
        });
    }
}
