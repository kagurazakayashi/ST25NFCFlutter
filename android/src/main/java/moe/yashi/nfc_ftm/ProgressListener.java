package moe.yashi.nfc_ftm;

import android.util.Log;

import com.st.st25sdk.ftmprotocol.FtmProtocol;

import android.util.Log;

public class ProgressListener implements FtmProtocol.TransferProgressionListener {
    private final String TAG = "ProgressListener";
    private NfcFtmPlugin ftmP;

    public ProgressListener(NfcFtmPlugin nfcFtmP) {
        ftmP = nfcFtmP;
    }

    @Override
    public void transmissionProgress(int transmittedBytes, int acknowledgedBytes, int totalSize) {
        ftmP.sendProgressData(true, transmittedBytes, acknowledgedBytes, totalSize);
    }

    @Override
    public void receptionProgress(int receivedBytes, int acknowledgedBytes, int totalSize) {
        ftmP.sendProgressData(false, receivedBytes, acknowledgedBytes, totalSize);
    }
}
