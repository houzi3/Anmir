package io.github.houzi3.anmir.connect;

import android.Manifest;
import android.app.Activity;
import android.app.Dialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.TextView;

/** A small native companion: service readiness, not a click, drives success feedback. */
public final class MainActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView status;
    private Button primary;
    private View stop, forget, retry;
    private TextView hint;
    private GradientDrawable dot;
    private Dialog feedback;
    private boolean resumed;
    private boolean pendingLaunch;
    private boolean permissionPending;
    private long expectedGeneration;
    private long startDeadline;
    private long feedbackUntil;
    private int localMessage;

    private final Runnable jump = () -> {
        if (!resumed || !pendingLaunch) { return; }
        pendingLaunch = false; // Consume before leaving; returning must never launch again.
        feedbackUntil = 0;
        dismissFeedback();
        openSettings();
    };
    private final Runnable refresh = new Runnable() {
        @Override public void run() {
            if (!resumed) { return; }
            if (pendingLaunch && !permissionPending) {
                if (RelayService.generation >= expectedGeneration && RelayService.ready && RelayService.running) {
                    showFeedback();
                } else if ((RelayService.generation >= expectedGeneration && !RelayService.running)
                        || SystemClock.elapsedRealtime() >= startDeadline) {
                    pendingLaunch = false;
                    feedbackUntil = 0;
                    handler.removeCallbacks(jump);
                    dismissFeedback();
                    localMessage = RelayService.status == R.string.discovery_failed
                            || RelayService.status == R.string.wifi_required
                            ? RelayService.status : R.string.start_failed;
                    stopService(new Intent(MainActivity.this, RelayService.class));
                }
            }
            render();
            handler.postDelayed(this, pendingLaunch ? 100 : 500);
        }
    };

    @SuppressWarnings("deprecation") // Android 15+ enforces edge-to-edge; older devices need this call.
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (Build.VERSION.SDK_INT < 35) { getWindow().setDecorFitsSystemWindows(false); }
        setContentView(R.layout.activity_main);
        findViewById(R.id.page).setOnApplyWindowInsetsListener((view, insets) -> {
            Insets safe = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            view.setPadding(safe.left, safe.top, safe.right, safe.bottom);
            return insets;
        });
        if (state != null) {
            pendingLaunch = state.getBoolean("pending");
            permissionPending = state.getBoolean("permission");
            expectedGeneration = state.getLong("generation");
            startDeadline = state.getLong("deadline");
            feedbackUntil = state.getLong("feedbackUntil");
            localMessage = state.getInt("message");
        }
        status = findViewById(R.id.status);
        primary = findViewById(R.id.primary);
        stop = findViewById(R.id.stop);
        forget = findViewById(R.id.forget);
        retry = findViewById(R.id.retry);
        retry.setOnClickListener(view -> {
            localMessage = 0;
            startService(new Intent(this, RelayService.class).setAction("retry"));
            render();
        });
        forget.setOnClickListener(view -> {
            if (RelayService.running) { startService(new Intent(this, RelayService.class).setAction("forget")); }
            else {
                getSharedPreferences("reconnect", MODE_PRIVATE).edit().remove("mac").apply();
                RelayService.remembered = false;
            }
            localMessage = 0;
            render();
        });
        hint = findViewById(R.id.footer_hint);
        dot = new GradientDrawable();
        dot.setShape(GradientDrawable.OVAL);
        findViewById(R.id.status_dot).setBackground(dot);
        primary.setOnClickListener(view -> {
            localMessage = 0;
            if (RelayService.running && RelayService.ready) { openSettings(); return; }
            pendingLaunch = true;
            expectedGeneration = RelayService.generation + (RelayService.running ? 0 : 1);
            if (Build.VERSION.SDK_INT >= 33
                    && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                permissionPending = true;
                requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, 1);
            } else { startHelper(); }
            render();
        });
        stop.setOnClickListener(view -> {
            pendingLaunch = false;
            localMessage = 0;
            handler.removeCallbacks(jump);
            dismissFeedback();
            stopService(new Intent(this, RelayService.class));
        });
        render();
    }

    private void startHelper() {
        startDeadline = SystemClock.elapsedRealtime() + 15_000;
        try { startForegroundService(new Intent(this, RelayService.class)); }
        catch (RuntimeException failure) {
            pendingLaunch = false;
            localMessage = R.string.start_failed;
        }
    }

    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        if (request == 1 && permissionPending) {
            permissionPending = false;
            // Notification denial does not prevent a connected-device foreground service.
            if (pendingLaunch) { startHelper(); }
        }
    }

    private void render() {
        boolean running = RelayService.running;
        boolean ready = running && RelayService.ready;
        boolean starting = pendingLaunch || (running && !ready);
        int message = localMessage != 0 ? localMessage : starting && !ready ? R.string.starting : RelayService.status;
        if (!getString(message).contentEquals(status.getText())) { status.setText(message); }
        boolean error = message == R.string.start_failed || message == R.string.discovery_failed
                || message == R.string.wifi_required || message == R.string.failed
                || message == R.string.window_unavailable || message == R.string.settings_unavailable;
        status.setTextColor(getColor(error ? R.color.error : R.color.muted));
        dot.setColor(getColor(error ? R.color.error : ready ? R.color.mint : R.color.muted));
        primary.setText(starting && !ready ? R.string.starting : ready ? R.string.open_settings : R.string.start);
        primary.setEnabled(!starting);
        primary.setAlpha(starting ? .65f : 1f);
        stop.setVisibility(running ? View.VISIBLE : View.GONE);
        boolean savedMac = getSharedPreferences("reconnect", MODE_PRIVATE).contains("mac");
        forget.setVisibility(savedMac ? View.VISIBLE : View.GONE);
        retry.setVisibility(running && savedMac ? View.VISIBLE : View.GONE);
        retry.setEnabled(!RelayService.retrying);
        retry.setAlpha(RelayService.retrying ? .65f : 1f);
        hint.setVisibility(running ? View.GONE : View.VISIBLE);
    }

    private void showFeedback() {
        if (feedback != null) { return; }
        if (feedbackUntil == 0) { feedbackUntil = SystemClock.elapsedRealtime() + 1200; }
        feedback = new Dialog(this);
        feedback.setContentView(R.layout.dialog_started);
        feedback.setCancelable(false);
        feedback.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        feedback.getWindow().addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        feedback.getWindow().setDimAmount(.55f);
        feedback.show();
        int width = Math.min(dp(312), getResources().getDisplayMetrics().widthPixels - dp(48));
        feedback.getWindow().setLayout(width, WindowManager.LayoutParams.WRAP_CONTENT);
        handler.postDelayed(jump, Math.max(0, feedbackUntil - SystemClock.elapsedRealtime()));
    }

    private void dismissFeedback() {
        if (feedback != null) { feedback.dismiss(); feedback = null; }
    }

    private void openSettings() {
        try {
            // AOSP Settings can scroll to and highlight this preference. OEM Settings
            // may ignore these optional hints and still open Developer options normally.
            String argumentKey = ":settings:fragment_args_key";
            Bundle arguments = new Bundle();
            arguments.putString(argumentKey, "toggle_adb_wireless");
            // Keep Settings' own task. Recreate a standard Developer options Activity
            // so a previously consumed highlight request runs again on each visit.
            startActivity(new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                    .putExtra(argumentKey, "toggle_adb_wireless")
                    .putExtra(":settings:show_fragment_args", arguments)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP));
        }
        catch (ActivityNotFoundException | SecurityException unavailable) {
            try {
                startActivity(new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            } catch (ActivityNotFoundException | SecurityException alsoUnavailable) {
                localMessage = R.string.settings_unavailable;
                render();
            }
        }
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }

    @Override public void onSaveInstanceState(Bundle state) {
        state.putBoolean("pending", pendingLaunch);
        state.putBoolean("permission", permissionPending);
        state.putLong("generation", expectedGeneration);
        state.putLong("deadline", startDeadline);
        state.putLong("feedbackUntil", feedbackUntil);
        state.putInt("message", localMessage);
        super.onSaveInstanceState(state);
    }

    @Override public void onResume() {
        super.onResume();
        resumed = true;
        handler.post(refresh);
    }

    @Override public void onPause() {
        resumed = false;
        handler.removeCallbacks(refresh);
        handler.removeCallbacks(jump);
        dismissFeedback();
        super.onPause();
    }

    @Override public void onStop() {
        if (!isChangingConfigurations() && !permissionPending) {
            pendingLaunch = false; // Backgrounding cancels only automatic navigation, not the helper.
            feedbackUntil = 0;
        }
        super.onStop();
    }
}
