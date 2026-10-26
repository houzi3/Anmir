package io.github.houzi3.anmir.connect;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.Instrumentation;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Button;
import java.io.File;
import java.io.FileOutputStream;
import java.util.function.BooleanSupplier;

/** Real startup and activity lifecycle coverage, with no pairing or saved device addresses. */
public final class CompanionSmokeTest extends Instrumentation {
    private MainActivity activity;
    private boolean requireWirelessTarget;
    private void check(boolean value, String message) {
        if (!value) { throw new AssertionError(message); }
    }
    private void await(BooleanSupplier condition, long timeout, String message) {
        long end = SystemClock.elapsedRealtime() + timeout;
        while (!condition.getAsBoolean() && SystemClock.elapsedRealtime() < end) { SystemClock.sleep(40); }
        check(condition.getAsBoolean(), message);
    }
    private String activePackage() {
        AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
        return root == null || root.getPackageName() == null ? "" : root.getPackageName().toString();
    }
    private boolean successVisible() {
        AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
        if (root != null && root.getPackageName() != null
                && root.getPackageName().toString().contains("permissioncontroller")) {
            // Exercise the first-run notification permission through its normal system UI.
            for (String prefix : new String[] {"com.android.permissioncontroller", "com.google.android.permissioncontroller"}) {
                for (AccessibilityNodeInfo button : root.findAccessibilityNodeInfosByViewId(prefix + ":id/permission_allow_button")) {
                    button.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                }
            }
        }
        return root != null && !root.findAccessibilityNodeInfosByText(
                getTargetContext().getString(R.string.start_success)).isEmpty();
    }
    private void capture(String name) throws Exception {
        Bitmap bitmap = getUiAutomation().takeScreenshot();
        check(bitmap != null, "Screenshot unavailable");
        File folder = new File(getTargetContext().getCacheDir(), "ui-validation");
        check(folder.isDirectory() || folder.mkdirs(), "Screenshot directory unavailable");
        try (FileOutputStream output = new FileOutputStream(new File(folder, name + ".png"))) {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output);
        } finally { bitmap.recycle(); }
    }
    private void click(int id) { runOnMainSync(() -> activity.findViewById(id).performClick()); }
    private ActivityManager.AppTask helperTask() {
        for (ActivityManager.AppTask task : getTargetContext().getSystemService(ActivityManager.class).getAppTasks()) {
            if (task.getTaskInfo().taskId == activity.getTaskId()) { return task; }
        }
        throw new AssertionError("The companion task was lost");
    }
    private void checkSettingsTask(String settings) {
        check(activePackage().equals(settings), "Settings is not visible");
        ActivityManager.RecentTaskInfo task = helperTask().getTaskInfo();
        check(task.numActivities == 1, "Settings joined the companion back stack");
        check(task.topActivity != null && task.topActivity.getPackageName().equals(getTargetContext().getPackageName()),
                "The companion task is topped by Settings");
        if (requireWirelessTarget) {
            await(this::wirelessDebuggingVisible, 5000, "Wireless debugging was not brought into view");
        }
    }
    private boolean wirelessDebuggingVisible() {
        AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
        if (root == null) { return false; }
        for (String label : new String[]{"无线调试", "無線偵錯", "Wireless debugging"}) {
            for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText(label)) {
                if (node.isVisibleToUser()) { return true; }
            }
        }
        return false;
    }
    private boolean scrollBackward(AccessibilityNodeInfo node) {
        if (node == null) { return false; }
        if (node.isScrollable() && node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)) { return true; }
        for (int i = 0; i < node.getChildCount(); ++i) {
            if (scrollBackward(node.getChild(i))) { return true; }
        }
        return false;
    }
    private void moveSettingsAwayFromTarget() {
        if (!requireWirelessTarget) { return; }
        for (int i = 0; i < 8 && scrollBackward(getUiAutomation().getRootInActiveWindow()); ++i) { SystemClock.sleep(150); }
        SystemClock.sleep(300);
    }
    private void returnToHelper() {
        runOnMainSync(() -> helperTask().moveToFront()); // Simulate selecting the companion in Recents.
        await(() -> activePackage().equals(getTargetContext().getPackageName()), 5000, "Could not return to helper");
        SystemClock.sleep(1800);
        check(activePackage().equals(getTargetContext().getPackageName()), "Returning reopened Settings");
    }
    @Override public void onCreate(Bundle args) {
        super.onCreate(args);
        requireWirelessTarget = args != null && "true".equals(args.getString("require_wireless_target"));
        start();
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            activity = (MainActivity) startActivitySync(new Intent(getTargetContext(), MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            waitForIdleSync();
            SystemClock.sleep(500); // Capture settled activity and dialog frames, not enter animations.
            runOnMainSync(() -> {
                check(((Button) activity.findViewById(R.id.primary)).getText()
                        .equals(activity.getString(R.string.start)), "Idle primary action is wrong");
                float density = activity.getResources().getDisplayMetrics().density;
                int[] point = new int[2];
                activity.findViewById(R.id.mac_step).getLocationOnScreen(point);
                check(point[1] / density < 290, "The header is no longer compact");
                check(activity.findViewById(R.id.heading).getHeight() / density < 65, "Oversized hero title");
            });
            capture("home");
            click(R.id.primary);
            await(this::successVisible, 10000, "No readiness success feedback");
            check(RelayService.ready && RelayService.running, "Success was shown before service readiness");
            SystemClock.sleep(300);
            capture("startup-success");
            String settings = new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                    .resolveActivity(getTargetContext().getPackageManager()).getPackageName();
            await(() -> activePackage().equals(settings), 8000, "Developer options did not open automatically");
            checkSettingsTask(settings);
            if (requireWirelessTarget) {
                SystemClock.sleep(600); // Finish Settings' entry and scroll animations.
                capture("settings-wireless");
            }
            moveSettingsAwayFromTarget();
            returnToHelper();
            runOnMainSync(() -> check(((Button) activity.findViewById(R.id.primary)).getText()
                    .equals(activity.getString(R.string.open_settings)), "Running action is wrong"));
            capture("running");
            click(R.id.primary); // The manual Settings action must use the same task separation.
            await(() -> activePackage().equals(settings), 8000, "Manual Developer options did not open");
            checkSettingsTask(settings);
            moveSettingsAwayFromTarget();
            returnToHelper();
            long generation = RelayService.generation;
            click(R.id.stop);
            await(() -> !RelayService.running, 5000, "Stop did not stop the helper");
            SystemClock.sleep(600);
            click(R.id.primary);
            await(this::successVisible, 10000, "Restart did not show readiness feedback");
            check(RelayService.generation > generation, "Restart reused stale service readiness");
            await(() -> activePackage().equals(settings), 8000, "Restart did not open Developer options");
            checkSettingsTask(settings);
            returnToHelper();
            click(R.id.stop);
            await(() -> !RelayService.running, 5000, "Final cleanup failed");
            result.putString("stream", "PASS: compact layout; real readiness feedback; automatic and manual Settings in a separate task; companion task retains only its Activity; return via Recents without relaunch; stop and restart. "
                    + (requireWirelessTarget ? "Wireless debugging is visible after automatic and manual navigation. " : "")
                    + "Screenshots: cache/ui-validation.\n");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable failure) {
            getTargetContext().stopService(new Intent(getTargetContext(), RelayService.class));
            result.putString("stream", "FAIL: " + android.util.Log.getStackTraceString(failure));
            finish(Activity.RESULT_CANCELED, result);
        }
    }
}
