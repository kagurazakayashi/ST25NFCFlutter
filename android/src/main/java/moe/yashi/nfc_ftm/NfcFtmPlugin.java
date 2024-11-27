package moe.yashi.nfc_ftm;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;

import io.flutter.embedding.android.FlutterActivity;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.PluginRegistry.Registrar;

import android.app.Activity;

import android.content.Context;
import android.content.Intent;

import android.nfc.NfcManager;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.IsoDep;
import android.nfc.tech.MifareClassic;
import android.nfc.tech.NfcA;

import com.st.st25android.AndroidReaderInterface;
import com.st.st25sdk.Helper;

import com.st.st25sdk.NFCTag;

import com.st.st25sdk.STException;

import com.st.st25sdk.iso14443b.Iso14443bTag;
import com.st.st25sdk.type2.Type2Tag;
import com.st.st25sdk.type2.st25tn.ST25TNTag;
import com.st.st25sdk.type4a.Type4Tag;
import com.st.st25sdk.type4a.Type4aTag;
import com.st.st25sdk.type4a.m24srtahighdensity.M24SR02KTag;
import com.st.st25sdk.type4a.m24srtahighdensity.M24SR04KTag;
import com.st.st25sdk.type4a.m24srtahighdensity.M24SR16KTag;
import com.st.st25sdk.type4a.m24srtahighdensity.M24SR64KTag;
import com.st.st25sdk.type4a.m24srtahighdensity.ST25TA16KTag;
import com.st.st25sdk.type4a.m24srtahighdensity.ST25TA64KTag;
import com.st.st25sdk.type4a.st25ta.ST25TA02KDTag;
import com.st.st25sdk.type4a.st25ta.ST25TA02KBDTag;
import com.st.st25sdk.type4a.st25ta.ST25TA02KBPTag;
import com.st.st25sdk.type4a.st25ta.ST25TA02KBTag;
import com.st.st25sdk.type4a.st25ta.ST25TA02KPTag;
import com.st.st25sdk.type4a.st25ta.ST25TA02KTag;
import com.st.st25sdk.type4a.st25ta.ST25TA512BTag;
import com.st.st25sdk.type4a.st25ta.ST25TA512Tag;
import com.st.st25sdk.type4b.Type4bTag;
import com.st.st25sdk.type5.STType5Tag;
import com.st.st25sdk.type5.Type5Tag;
import com.st.st25sdk.type5.lri.LRi1KTag;
import com.st.st25sdk.type5.lri.LRi2KTag;
import com.st.st25sdk.type5.lri.LRi512Tag;
import com.st.st25sdk.type5.lri.LRiS2KTag;
import com.st.st25sdk.type5.m24lr.LRiS64KTag;
import com.st.st25sdk.type5.m24lr.M24LR04KTag;
import com.st.st25sdk.type5.m24lr.M24LR16KTag;
import com.st.st25sdk.type5.m24lr.M24LR64KTag;
import com.st.st25sdk.type5.st25dv.ST25DVCTag;
import com.st.st25sdk.type5.st25dv.ST25DVTag;
import com.st.st25sdk.type5.st25dv.ST25TV04KPTag;
import com.st.st25sdk.type5.st25dv.ST25TV16KTag;
import com.st.st25sdk.type5.st25dv.ST25TV64KTag;
import com.st.st25sdk.type5.st25dv.ST25TV16KCTag;
import com.st.st25sdk.type5.st25dv.ST25TV64KCTag;
import com.st.st25sdk.type5.st25dvpwm.ST25DV02KW1Tag;
import com.st.st25sdk.type5.st25dvpwm.ST25DV02KW2Tag;
import com.st.st25sdk.type5.st25tv.ST25TVTag;
import com.st.st25sdk.type5.st25tvc.ST25TVCTag;

import com.st.st25sdk.ftmprotocol.FtmCommands;
//import com.st.st25sdk.ftmprotocol.FtmProtocol;
import com.st.st25sdk.TagHelper;
//import com.st.st25sdk.TagHelper.ProductID;

import com.st.st25sdk.ndef.NDEFMsg;
import com.st.st25sdk.ndef.NDEFRecord;

import static com.st.st25sdk.TagHelper.ProductID.PRODUCT_UNKNOWN;
import static com.st.st25sdk.TagHelper.identifyIso14443BProduct;
import static com.st.st25sdk.TagHelper.identifyIso14443aType2Type4aProduct;
import static com.st.st25sdk.TagHelper.identifyType4Product;
import static com.st.st25sdk.TagHelper.identifyTypeVProduct;

import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;
import androidx.lifecycle.ViewModel;
import androidx.lifecycle.LifecycleOwner;

import android.util.Log;

/** NfcFtmPlugin */
public class NfcFtmPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware, EventChannel.StreamHandler {
  // 接收来自 Flutter 的通知，可以回复该通知
  private MethodChannel methodChannel;
  private EventChannel.EventSink eventChannelSink = null;
  private Handler progressHandle; // 子线程与主线程交互
  private ProgressViewModel progressViewModel;

  private Activity activity; // 用于存储当前的 Activity
  private Context context; // 用于存储 ApplicationContext

  private NfcAdapter mnfcAdapter;

  // private Tag mandroidTag;

  public static class TagInfo {
    public NFCTag nfcTag;
    public TagHelper.ProductID productID;
  }

  private ST25DVTag mST25DVTag;
  private FtmCommands mFtmCommands; // FTM 模式命令

  private ProgressListener pListener; // FTM 模式下的进度

  private Boolean isFTMmode = false; // 是否使用 FTM 模式

  private final String TAG = "NfcFtmPlugin";
  public static final byte FTM_CMD_GET_BOARD_INFO = 0;
  public static final byte FTM_CMD_SEND_DATA = 5;
  public static final byte FTM_CMD_READ_DATA = 6;
  private static final int UPDATE_PROGRESS = 1;

  // 创建线程池
  ExecutorService executorService = Executors.newSingleThreadExecutor();

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    Log.w(TAG, String.format(">>>>> onAttachedToEngine %s", "test"));
    context = flutterPluginBinding.getApplicationContext();

    methodChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "nfc_ftm_to_native");
    methodChannel.setMethodCallHandler(this);

    // 可以随时发送的通知
    EventChannel eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "nfc_ftm_to_flutter");
    eventChannel.setStreamHandler(this);
  }

  @Override
  // 接收 Flutter 的通知，call.method 是通知名称
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    String method = call.method;
    switch (method) {
      case "isAvailable":
        boolean isEnabledNFC = isNfcSupported(context);
        Log.w(TAG, String.format(">>>>> isEnabledNFC %s", isEnabledNFC));
        sendToastMessage(String.format("isEnabledNFC: %s", isEnabledNFC));
        result.success(isEnabledNFC);
        break;
      case "openNFC":
        isFTMmode = false;
        if (mFtmCommands != null) {
          mFtmCommands.cancelCurrentTransfer();
          mFtmCommands = null;
        }
        openNFC(result);
        result.success(true);
        break;
      case "closeNFC":
        boolean isDone = disableReaderMode();
        result.success(isDone);
        break;
      case "openFTM":
        isFTMmode = true;
        if (mFtmCommands != null) {
          mFtmCommands.cancelCurrentTransfer();
          mFtmCommands = null;
        }
        openNFC(result);
        result.success(true);
        break;
      case "getFTM":
        if (mST25DVTag == null) {
          result.success(false);
          return;
        }
        initFTM();
        result.success(true);
        break;
      case "sendFTMData":
        byte[] sendData = (byte[]) call.argument("data");
        handleFTMOperation(result, FTM_CMD_SEND_DATA, sendData);
        break;
      case "readFTMData":
        byte[] rsendData = (byte[]) call.argument("data");
        handleFTMOperation(result, FTM_CMD_READ_DATA, rsendData);
        break;
      case "FTMcancel":
        if (mFtmCommands == null) {
          return;
        }
        mFtmCommands.cancelCurrentTransfer();
        break;
      case "NDEF@read":
        readNdef(result);
        break;

      default:
        result.notImplemented();
    }
  }

  //
  public boolean openNFC(@NonNull Result result) {
    boolean isEnabledNFC = isNfcSupported(context);
    if (!isEnabledNFC) {
      sendToastMessage("NFC no found");
      result.success(isEnabledNFC);
      return false;
    }
    initNFCAdapter();
    if (mnfcAdapter == null) {
      sendToastMessage("mnfcAdapter no found!");
      result.success(false);
      return false;
    }
    enableReaderMode();
    return true;
  }

  public void initFTM() {
    if (mFtmCommands != null) {
      mFtmCommands.cancelCurrentTransfer();
      mFtmCommands = null;
    }
    try {
      mFtmCommands = new FtmCommands(mST25DVTag);
      mFtmCommands.setMinTimeInMsBetweenConsecutiveCmds(80);
    } catch (Exception e) {
      Log.e(TAG, "FtmCommands init Err:" + e.getMessage());
    }

    if (mFtmCommands == null) {
      Log.e(TAG, "initFTM: mFtmCommands == null");
      sendToastMessage("initFTM: mFtmCommands == null");
    }
  }

  public byte[] FTMrwData(byte cmd, byte[] sendData) throws Exception {
    if (mFtmCommands == null) {
      Log.e(TAG, "sendFTMData: mFtmCommands == null");
      throw new Exception("Send FTM data error: mFtmCommands == null");
    }
    byte[] reData;
    try {
      reData = mFtmCommands.sendCmdAndWaitForCompletion(cmd, sendData,
          true, true, pListener,
          10000);
    } catch (STException e) {
      String eStr = e.getMessage();
      if (eStr.equals("CMD_FAILED")) {
        mFtmCommands.cancelCurrentTransfer();
      }
      // 处理异常（例如，打印错误日志）
      e.printStackTrace();
      Log.e(TAG, String.format("*** send STException: %s", e.getMessage()));
      throw new Exception("NO_FTM_MODE");
      // 你可以根据需要采取适当的操作，比如返回默认值或者重新抛出
    } catch (InterruptedException e) {
      Log.e(TAG, String.format("*** send InterruptedException: %s", e.getMessage()));
      throw new Exception(String.format("Send FTM data InterruptedException: %s", e.getMessage()));
      // 由于线程被中断，通常你可能想恢复中断状态
    }
    return reData;
  }

  // 创建一个线程池，用于执行FTM发送数据任务
  private void handleFTMOperation(MethodChannel.Result result, byte cmd, byte[] data) {
    Future<byte[]> future = executorService.submit(new Callable<byte[]>() {
      @Override
      public byte[] call() throws Exception {
        try {
          return FTMrwData(cmd, data);
        } catch (Exception e) {
          e.printStackTrace();
          Log.w(TAG, String.format(">>>>> sendFTMData Exception %s", e.getMessage()));
          sendToastMessage(e.getMessage());
          return null;
        }
      }
    });

    byte[] responseData = new byte[0];
    try {
      responseData = future.get();
      if (responseData == null) {
        Log.w(TAG, ">>>>> send back is null");
        sendToastMessage("Response data is null");
      }
    } catch (Exception e) {
      e.printStackTrace();
      Log.w(TAG, String.format(">>>>> send back Exception %s", e.getMessage()));
      sendToastMessage(String.format("future.get() Exception: %s", e.getMessage()));
    }
    executorService.shutdown();
    result.success(responseData);
  }

  public void sendToastMessage(String message) {
    Map<String, String> messageMap = new HashMap();
    messageMap.put("k", "botToast");
    messageMap.put("v", message);
    activity.runOnUiThread(new Runnable() {
      @Override
      public void run() {
        eventChannelSink.success(messageMap);
      }
    });
  }

  @Override
  // eventChannelSink
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    methodChannel.setMethodCallHandler(null);
  }

  @Override
  public void onDetachedFromActivity() {
    // 完全解绑 Activity
    Log.w(TAG, ">>>>> onDetachedFromActivity");
    activity = null; // 清理 Activity 引用
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding activityPluginBinding) {
    // 配置恢复时重新绑定 Activity
    Log.w(TAG, ">>>>> onReattachedToActivityForConfigChanges");
    activity = activityPluginBinding.getActivity(); // 恢复 Activity 引用
    // getTag();
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    // 配置更改时解绑 Activity
    Log.w(TAG, ">>>>> onDetachedFromActivityForConfigChanges");
    activity = null; // 清理 Activity 引用
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding activityPluginBinding) {
    // 绑定 Activity 的逻辑
    Log.w(TAG, ">>>>> onAttachedToActivity");
    activity = activityPluginBinding.getActivity(); // 获取当前的 Activity
    // getTag();

    if (activity instanceof LifecycleOwner) {
      LifecycleOwner lifecycleOwner = (LifecycleOwner) activity;
      progressViewModel.getProgress().observe(lifecycleOwner, data -> {
        // 更新 UI 或其他操作
        Log.i(TAG, ">>>R4");
      });
    } else {
      Log.i(TAG, "Activity must implement LifecycleOwner");
      throw new IllegalArgumentException("Activity must implement LifecycleOwner");
    }
  }

  @Override
  // eventChannelSink
  public void onListen(Object arguments, EventChannel.EventSink events) {
    eventChannelSink = events;
    progressHandle = new Handler(Looper.getMainLooper()) {
      @Override
      public void handleMessage(Message msg) {

        Log.i(TAG, String.format(">>>RRRR %d %d %d", msg.what, msg.arg1, msg.arg2));
        if (msg.what == UPDATE_PROGRESS) {
          eventChannelSink.success(msg.obj);

        }
      }

    };

    // LifecycleOwner lifecycleOwner = (LifecycleOwner) activity; // 强制转换为
    // LifecycleOwner
    // progressViewModel.getProgress().observe(lifecycleOwner, data -> {
    // // 更新 UI 或其他操作
    // Log.i(TAG, ">>>R4");
    // });

    pListener = new ProgressListener(this);
  }

  // 判断NFC标签是否可用
  public static boolean isNfcSupported(Context context) {
    NfcManager nfcManager = null;
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.GINGERBREAD_MR1) {
      return false;
    }
    nfcManager = (NfcManager) context.getSystemService(Context.NFC_SERVICE);
    NfcAdapter nfcAdapter = nfcManager != null ? nfcManager.getDefaultAdapter() : null;
    return nfcAdapter != null && nfcAdapter.isEnabled();
  }

  // 初始化 NFC
  public void initNFCAdapter() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.GINGERBREAD_MR1) {
      return;
    }
    NfcManager nfcManager = (NfcManager) activity.getSystemService(Activity.NFC_SERVICE);
    mnfcAdapter = nfcManager.getDefaultAdapter();
  }

  // 开启 NFC 扫描
  public void enableReaderMode() {
    Intent intent = new Intent(activity, activity.getClass());
    intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);

    // mnfcAdapter.enableForegroundDispatch(activity,
    // PendingIntent.getActivity(activity, 0, intent, 0), null, null);

    // // 创建回调，用于接收 NFC 标签事件
    NfcAdapter.ReaderCallback readerCallback = null;
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
      return;
    }
    readerCallback = new NfcAdapter.ReaderCallback() {
      @Override
      public void onTagDiscovered(Tag tag) {
        // 当检测到 NFC 标签时触发
        byte[] uid = tag.getId();
        String androidTagIdHex = bytesToHex(uid);

        Map<String, Object> returnVal = new HashMap<>();
        // mandroidTag = tag;
        AndroidReaderInterface readerInterface = AndroidReaderInterface.newInstance(tag);

        TagInfo tagInfo = new TagInfo();
        tagInfo.nfcTag = null;
        tagInfo.productID = PRODUCT_UNKNOWN;

        try {
          switch (readerInterface.mTagType) {
            case NFC_TAG_TYPE_V:
              uid = Helper.reverseByteArray(uid);
              tagInfo.productID = identifyTypeVProduct(readerInterface, uid);
              break;
            case NFC_TAG_TYPE_4A:
              tagInfo.productID = identifyType4Product(readerInterface, uid);
              break;
            case NFC_TAG_TYPE_2:
              tagInfo.productID = identifyIso14443aType2Type4aProduct(readerInterface, uid);
              break;
            case NFC_TAG_TYPE_4B:
              tagInfo.productID = identifyIso14443BProduct(readerInterface, uid);
              break;
            case NFC_TAG_TYPE_A:
            case NFC_TAG_TYPE_B:
            default:
              tagInfo.productID = PRODUCT_UNKNOWN;
              break;
          }
        } catch (STException e) {
          // An STException has occured while instantiating the tag
          sendToastMessage(String.format("TagType err: %s", e.getMessage()));

          e.printStackTrace();
          tagInfo.productID = PRODUCT_UNKNOWN;
        }

        try {
          switch (tagInfo.productID) {
            case PRODUCT_ST_ST25DV64K_I:
            case PRODUCT_ST_ST25DV64K_J:
            case PRODUCT_ST_ST25DV16K_I:
            case PRODUCT_ST_ST25DV16K_J:
            case PRODUCT_ST_ST25DV04K_I:
            case PRODUCT_ST_ST25DV04K_J:
              tagInfo.nfcTag = new ST25DVTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25DV04KC_I:
            case PRODUCT_ST_ST25DV04KC_J:
            case PRODUCT_ST_ST25DV16KC_I:
            case PRODUCT_ST_ST25DV16KC_J:
            case PRODUCT_ST_ST25DV64KC_I:
            case PRODUCT_ST_ST25DV64KC_J:
              tagInfo.nfcTag = new ST25DVCTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TV16KC:
              tagInfo.nfcTag = new ST25TV16KCTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TV64KC:
              tagInfo.nfcTag = new ST25TV64KCTag(readerInterface, uid);
              break;

            case PRODUCT_ST_LRi512:
              tagInfo.nfcTag = new LRi512Tag(readerInterface, uid);
              break;
            case PRODUCT_ST_LRi1K:
              tagInfo.nfcTag = new LRi1KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_LRi2K:
              tagInfo.nfcTag = new LRi2KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_LRiS2K:
              tagInfo.nfcTag = new LRiS2KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_LRiS64K:
              tagInfo.nfcTag = new LRiS64KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_M24SR02_Y:
              tagInfo.nfcTag = new M24SR02KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_M24SR04_Y:
            case PRODUCT_ST_M24SR04_G:
              tagInfo.nfcTag = new M24SR04KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_M24SR16_Y:
              tagInfo.nfcTag = new M24SR16KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_M24SR64_Y:
              tagInfo.nfcTag = new M24SR64KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TV512:
            case PRODUCT_ST_ST25TV02K:
              tagInfo.nfcTag = new ST25TVTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TV04K_P:
              tagInfo.nfcTag = new ST25TV04KPTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TV02KC:
            case PRODUCT_ST_ST25TV512C:
              tagInfo.nfcTag = new ST25TVCTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TV16K:
              tagInfo.nfcTag = new ST25TV16KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TV64K:
              tagInfo.nfcTag = new ST25TV64KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25DV02K_W1:
              tagInfo.nfcTag = new ST25DV02KW1Tag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25DV02K_W2:
              tagInfo.nfcTag = new ST25DV02KW2Tag(readerInterface, uid);
              break;
            case PRODUCT_ST_M24LR16E_R:
              tagInfo.nfcTag = new M24LR16KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_M24LR64E_R:
            case PRODUCT_ST_M24LR64_R:
              tagInfo.nfcTag = new M24LR64KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_M24LR04E_R:
              tagInfo.nfcTag = new M24LR04KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA02K:
              tagInfo.nfcTag = new ST25TA02KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA02KB:
              tagInfo.nfcTag = new ST25TA02KBTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA02K_P:
              tagInfo.nfcTag = new ST25TA02KPTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA02KB_P:
              tagInfo.nfcTag = new ST25TA02KBPTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA02K_D:
              tagInfo.nfcTag = new ST25TA02KDTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA02KB_D:
              tagInfo.nfcTag = new ST25TA02KBDTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA16K:
              tagInfo.nfcTag = new ST25TA16KTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA512_K:
            case PRODUCT_ST_ST25TA512:
              tagInfo.nfcTag = new ST25TA512Tag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA512B:
              tagInfo.nfcTag = new ST25TA512BTag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TA64K:
              tagInfo.nfcTag = new ST25TA64KTag(readerInterface, uid);
              break;
            case PRODUCT_GENERIC_TYPE4:
              tagInfo.nfcTag = new Type4Tag(readerInterface, uid);
              break;
            case PRODUCT_GENERIC_TYPE4A:
              tagInfo.nfcTag = new Type4aTag(readerInterface, uid);
              break;
            case PRODUCT_GENERIC_TYPE4B:
              tagInfo.nfcTag = new Type4bTag(readerInterface, uid);
              break;
            case PRODUCT_GENERIC_ISO14443B:
              tagInfo.nfcTag = new Iso14443bTag(readerInterface, uid);
              break;
            case PRODUCT_GENERIC_TYPE5_AND_ISO15693:
              tagInfo.nfcTag = new STType5Tag(readerInterface, uid);
              break;
            case PRODUCT_GENERIC_TYPE5:
              tagInfo.nfcTag = new Type5Tag(readerInterface, uid);
              break;
            case PRODUCT_GENERIC_TYPE2:
              tagInfo.nfcTag = new Type2Tag(readerInterface, uid);
              break;
            case PRODUCT_ST_ST25TN01K:
            case PRODUCT_ST_ST25TN512:
              tagInfo.nfcTag = new ST25TNTag(readerInterface, uid);
              break;
            default:
              tagInfo.nfcTag = null;
              tagInfo.productID = PRODUCT_UNKNOWN;
              break;
          }
        } catch (STException e) {
          // An STException has occured while instantiating the tag
          sendToastMessage(String.format("ST25TVCTag err: %s", e.getMessage()));

          e.printStackTrace();
          tagInfo.productID = PRODUCT_UNKNOWN;
        }

        mST25DVTag = (ST25DVTag) tagInfo.nfcTag;
        if (isFTMmode) {
          initFTM();
        }
        int memSize = 0;
        int ndefLen = 0;
        try {
          memSize = mST25DVTag.getMemSizeInBytes();
          NDEFMsg ndefmsg = mST25DVTag.readNdefMessage();
          ndefLen = ndefmsg.getLength();

        } catch (STException e) {
          Log.e(TAG, String.format("MemSizeInBytes: %d", memSize));
        } catch (Exception e) {
          Log.e(TAG, String.format("NDEF Length: %d", ndefLen));
        }

        returnVal.put("k", "onDiscovered");

        returnVal.put("id", androidTagIdHex);
        returnVal.put("type", Arrays.toString(tag.getTechList()));
        returnVal.put("memSize", memSize);
        returnVal.put("ndefLength", ndefLen);

        activity.runOnUiThread(new Runnable() {
          public void run() {
            eventChannelSink.success(returnVal);
          }
        });
      }
    };
    // 配置 ReaderMode 参数
    int flags = NfcAdapter.FLAG_READER_NFC_A
        | NfcAdapter.FLAG_READER_NFC_B
        | NfcAdapter.FLAG_READER_NFC_F
        | NfcAdapter.FLAG_READER_NFC_V
        | NfcAdapter.FLAG_READER_NFC_BARCODE;
    mnfcAdapter.enableReaderMode(activity, readerCallback, flags, null);
  }

  // 关闭 NFC 扫描 关闭 FTM 通道
  public boolean disableReaderMode() {
    // mnfcAdapter.disableForegroundDispatch(activity);
    if (mFtmCommands != null) {
      mFtmCommands.cancelCurrentTransfer();
    }
    if (mnfcAdapter != null) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
        mnfcAdapter.disableReaderMode(activity);
      }
      return true;
    }
    return false;
  }

  // 从 ST25DVTag 对象中获取NDEF格式的信息
  private void readNdef(@NonNull Result result) {
    if (mST25DVTag == null) {
      return;
    }
    // 提交任务并返回 Future 对象
    Future<Map<String, Object>> future = executorService.submit(new Callable<Map<String, Object>>() {
      @Override
      public Map<String, Object> call() throws Exception {
        Map<String, Object> ndefData = new HashMap<>();

        try {
          NDEFMsg ndefmsg = mST25DVTag.readNdefMessage();
          for (NDEFRecord record : ndefmsg.getNDEFRecords()) {
            String payload = new String(record.getPayload(), StandardCharsets.UTF_8);
            ndefData.put("data", payload);
            ndefData.put("payload", record.getPayload());
          }
        } catch (STException e) {
          sendToastMessage("Read NDEF message STException: " + e.getMessage());
        } catch (Exception e) {
          sendToastMessage("Read NDEF message Exception: " + e.getMessage());
        }
        return ndefData;
      }
    });
    Map<String, Object> ndefData = new HashMap<>();
    try {
      ndefData = future.get();
      executorService.shutdown();
      if (ndefData != null) {
        result.success(ndefData);
      }
    } catch (Exception e) {
      e.printStackTrace();
      executorService.shutdown();
      result.error("Err", "readNDEF err", e);
    }
  }

  // 把自动数据转发给 Flutter
  public void sendProgressData(boolean isTransmitted, int tORrBytes, int acknowledgedBytes, int totalSize) {
    int progress = (acknowledgedBytes * 100) / totalSize;
    int secondaryProgress = (tORrBytes * 100) / totalSize;

    if (eventChannelSink != null) {
      Map<String, Object> data = new HashMap<>();
      data.put("progress", progress);
      data.put("secondaryProgress", secondaryProgress);
      if (isTransmitted) {
        data.put("k", "transmissionProgress");
        data.put("transmittedBytes", tORrBytes);
        Log.i(TAG, String.format(">>>T:%d / %d bytes | %d %% | %d %%", tORrBytes, totalSize, progress,
            secondaryProgress));
      } else {
        data.put("k", "receptionProgress");
        data.put("receivedBytes", tORrBytes);
        Log.i(TAG, String.format(">>>R:%d / %d bytes | %d %% | %d %%", tORrBytes, totalSize, progress,
            secondaryProgress));
      }
      data.put("acknowledgedBytes", acknowledgedBytes);
      data.put("totalSize", totalSize);

      // 使用 Handler 发送消息
      Message msg = progressHandle.obtainMessage(UPDATE_PROGRESS, progress,
          secondaryProgress, data);
      progressHandle.sendMessage(msg);

      // activity.runOnUiThread(new Runnable() {
      // public void run() {
      // Log.i(TAG, ">>>R3");
      // // eventChannelSink.success(data);
      // }
      // });

      if (progressViewModel != null) {
        // 更新 LiveData，通知 UI 线程更新
        progressViewModel.updateProgress(data);
      }
    }
  }

  private String bytesToHex(byte[] bytes) {
    StringBuilder hexString = new StringBuilder();
    for (byte b : bytes) {
      String hex = Integer.toHexString(0xFF & b);
      if (hex.length() == 1) {
        hexString.append('0');
      }
      hexString.append(hex);
    }
    return hexString.toString();
  }

  public static class ProgressViewModel extends ViewModel {
    private final MutableLiveData<Map<String, Object>> progress = new MutableLiveData<>();

    public MutableLiveData<Map<String, Object>> getProgress() {
      return progress;
    }

    // 更新 LiveData 中的 Map 数据
    public void updateProgress(Map<String, Object> data) {
      progress.postValue(data); // postValue 适用于后台线程更新数据
    }
  }

  @Override
  // eventChannelSink
  public void onCancel(Object arguments) {
    eventChannelSink = null;
    pListener = null;
    disableReaderMode();
  }
}
