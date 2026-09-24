package com.scrcpy.bridge;

import android.app.Activity;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.util.Base64;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Headless helper: dumps third-party apps (name / package / icon PNG base64)
 * to app-private files/scrcpy_apps.json for desktop-app via adb run-as.
 */
public class MainActivity extends Activity {
    private static final String TAG = "ScrcpyBridge";
    private static final String OUT_NAME = "scrcpy_apps.json";
    private static final int ICON_SIZE = 128;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            exportAppList();
        } catch (Exception e) {
            Log.e(TAG, "export failed", e);
        }
        finish();
    }

    private void exportAppList() throws Exception {
        PackageManager pm = getPackageManager();
        List<ApplicationInfo> apps = pm.getInstalledApplications(0);
        JSONArray arr = new JSONArray();

        for (ApplicationInfo info : apps) {
            // Only third-party / user apps
            if ((info.flags & ApplicationInfo.FLAG_SYSTEM) != 0) {
                continue;
            }

            JSONObject o = new JSONObject();
            CharSequence label = pm.getApplicationLabel(info);
            o.put("name", label != null ? label.toString() : info.packageName);
            o.put("packageName", info.packageName);
            o.put("system", false);

            String icon = iconToBase64(pm, info);
            if (icon != null) {
                o.put("icon", icon);
            }
            arr.put(o);
        }

        File out = new File(getFilesDir(), OUT_NAME);
        byte[] payload = arr.toString().getBytes(StandardCharsets.UTF_8);
        FileOutputStream fos = new FileOutputStream(out);
        try {
            OutputStreamWriter w = new OutputStreamWriter(fos, StandardCharsets.UTF_8);
            w.write(new String(payload, StandardCharsets.UTF_8));
            w.flush();
        } finally {
            fos.close();
        }
        Log.i(TAG, "wrote " + out.getAbsolutePath() + " thirdParty=" + arr.length()
                + " bytes=" + out.length());
    }

    private String iconToBase64(PackageManager pm, ApplicationInfo info) {
        try {
            Drawable d = pm.getApplicationIcon(info);
            Bitmap src = drawableToBitmap(d);
            if (src == null) return null;
            Bitmap scaled = Bitmap.createScaledBitmap(src, ICON_SIZE, ICON_SIZE, true);
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            scaled.compress(Bitmap.CompressFormat.PNG, 90, baos);
            if (scaled != src) scaled.recycle();
            return Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP);
        } catch (Exception e) {
            Log.w(TAG, "icon fail " + info.packageName, e);
            return null;
        }
    }

    private Bitmap drawableToBitmap(Drawable d) {
        if (d instanceof BitmapDrawable) {
            Bitmap b = ((BitmapDrawable) d).getBitmap();
            if (b != null) return b;
        }
        int w = d.getIntrinsicWidth();
        int h = d.getIntrinsicHeight();
        if (w <= 0) w = ICON_SIZE;
        if (h <= 0) h = ICON_SIZE;
        Bitmap bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        d.setBounds(0, 0, canvas.getWidth(), canvas.getHeight());
        d.draw(canvas);
        return bitmap;
    }
}
