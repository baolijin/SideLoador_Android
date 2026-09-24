// Mobile companion: returns installed app list (name / package / color)
// to the desktop bridge. Built as a minimal Android library-style app.
//
// Protocol (v0.1):
// 1. desktop-app: adb install -r scrcpy_bridge_mobile.apk
// 2. desktop-app: adb shell am start -n com.scrcpy.bridge/.MainActivity
// 3. mobile-app writes JSON to /data/local/tmp/scrcpy_apps.json
// 4. desktop-app reads that file

package_name = "com.scrcpy.bridge"
app_name = "Scrcpy Bridge Mobile"
