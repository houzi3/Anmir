package io.github.houzi3.anmir.connect;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.FileDescriptor;
import java.io.PrintWriter;
import java.net.Inet4Address;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Relays this phone's metadata; ADB keys, pairing passwords and shell access stay in ADB. */
public final class RelayService extends Service {
    public static volatile int status = R.string.idle;
    public static volatile boolean running, ready, remembered, retrying;
    public static volatile long generation;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Map<String, Connection> connections = new LinkedHashMap<>();
    private final Map<Integer, Long> verifiedPorts = new HashMap<>(); // Worker only.
    private final ArrayDeque<String> events = new ArrayDeque<>();
    private final LocalMdns.Stats mdnsStats = new LocalMdns.Stats();
    private volatile boolean active;
    private volatile int networkGeneration;
    private int verifiedGeneration = -1, failures;
    private boolean posting, callbackRegistered, retryRequested;
    private volatile String workerStage = "idle";
    private RelaySession session;
    private ReconnectTarget target;
    private String expiredSession, lastPorts = "";
    private int pairingPort, acceptedReports;
    private long sessionStarted, nextPost;
    private Inet4Address localAddress;
    private Network wifiNetwork;
    private Thread listener;
    private WifiManager.MulticastLock multicastLock;
    private ConnectivityManager connectivity;
    private final Runnable deadline = () -> { if (target == null) { stopSelf(); } };

    private static final class Connection {
        final String name;
        final int port;
        final long expires;
        Connection(LocalMdns.Record record) {
            name = RelaySession.connectionGuid(record.name); port = record.port;
            expires = SystemClock.elapsedRealtime() + Math.min(record.ttl, 30) * 1000;
        }
    }
    private void event(String value) {
        if (events.size() == 16) { events.removeFirst(); }
        events.add(value);
    }
    private SharedPreferences preferences() { return getSharedPreferences("reconnect", MODE_PRIVATE); }
    private ReconnectTarget loadTarget() {
        try {
            JSONObject value = new JSONObject(preferences().getString("mac", "{}"));
            return ReconnectTarget.create(value.optString("host"), value.optInt("port"),
                    value.optString("token"), value.optString("guid"));
        } catch (org.json.JSONException invalid) { return null; }
    }
    private boolean saveTarget(ReconnectTarget value) {
        try {
            return preferences().edit().putString("mac", new JSONObject().put("host", value.host)
                    .put("port", value.port).put("token", value.token).put("guid", value.guid).toString()).commit();
        } catch (org.json.JSONException invalid) { return false; }
    }
    private final ConnectivityManager.NetworkCallback networkCallback = new ConnectivityManager.NetworkCallback() {
        @Override public void onLinkPropertiesChanged(Network network, LinkProperties links) { updateNetwork(); }
        @Override public void onCapabilitiesChanged(Network network, NetworkCapabilities capabilities) { updateNetwork(); }
        @Override public void onLost(Network network) {
            if (network.equals(wifiNetwork)) { bindNetwork(null, null); }
            updateNetwork(network);
        }
    };
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (!active) { return; }
            if (session != null && SystemClock.elapsedRealtime() - sessionStarted > 120_000) {
                expiredSession = session.name; session = null; pairingPort = 0; nextPost = 0;
                if (target == null) { status = acceptedReports > 0 ? R.string.sent : R.string.expired; }
            }
            postPorts(); main.postDelayed(this, 2000);
        }
    };
    @Override public void onCreate() {
        super.onCreate(); ++generation; running = true; ready = false; status = R.string.starting;
        target = loadTarget(); remembered = target != null;
        NotificationManager manager = getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel("relay", "Anmir Connect", NotificationManager.IMPORTANCE_LOW));
        Notification notification = new Notification.Builder(this, "relay")
                .setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("Anmir Connect")
                .setContentText(getText(R.string.notification))
                .setContentIntent(PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE))
                .addAction(new Notification.Action.Builder(null, getText(R.string.stop),
                        PendingIntent.getService(this, 1, new Intent(this, RelayService.class).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)).build())
                .setOngoing(true).build();
        startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
        active = true;
        connectivity = getSystemService(ConnectivityManager.class);
        try {
            connectivity.registerNetworkCallback(new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), networkCallback, main);
            callbackRegistered = true;
            updateNetwork();
        } catch (SecurityException failure) { status = R.string.discovery_failed; stopSelf(); return; }
        // A remembered Mac may be resumed while offline. The foreground helper waits for Wi-Fi.
        if (target != null && wifiNetwork == null) { ready = true; status = R.string.waiting_wifi; }
        else if (wifiNetwork == null) { status = R.string.wifi_required; stopSelf(); return; }
        main.post(tick);
    }
    @SuppressWarnings("deprecation")
    private void updateNetwork() {
        updateNetwork(null);
    }
    @SuppressWarnings("deprecation")
    private void updateNetwork(Network excluded) {
        if (!active) { return; }
        for (Network network : connectivity.getAllNetworks()) {
            if (network.equals(excluded)) { continue; }
            NetworkCapabilities capabilities = connectivity.getNetworkCapabilities(network);
            LinkProperties links = connectivity.getLinkProperties(network);
            if (links == null || capabilities == null || !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
                    || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) { continue; }
            for (android.net.LinkAddress link : links.getLinkAddresses()) {
                if (link.getAddress() instanceof Inet4Address) {
                    bindNetwork(network, (Inet4Address) link.getAddress()); return;
                }
            }
        }
        bindNetwork(null, null);
    }
    private void bindNetwork(Network network, Inet4Address address) {
        if (java.util.Objects.equals(wifiNetwork, network) && java.util.Objects.equals(localAddress, address)) { return; }
        final int epoch = ++networkGeneration;
        if (listener != null) { listener.interrupt(); listener = null; }
        if (multicastLock != null && multicastLock.isHeld()) { multicastLock.release(); }
        wifiNetwork = network; localAddress = address; connections.clear();
        nextPost = 0; lastPorts = ""; failures = 0;
        if (network == null) { status = R.string.waiting_wifi; event("Wi-Fi unavailable"); return; }
        event("Wi-Fi listener generation=" + epoch);
        multicastLock = getApplicationContext().getSystemService(WifiManager.class).createMulticastLock("Anmir-local-discovery");
        multicastLock.setReferenceCounted(false);
        try { multicastLock.acquire(); }
        catch (SecurityException denied) { status = R.string.discovery_failed; stopSelf(); return; }
        listener = new Thread(() -> {
            try {
                LocalMdns.listen(address, network::bindSocket, mdnsStats, () -> active && epoch == networkGeneration,
                        () -> main.post(() -> {
                            if (active && epoch == networkGeneration) {
                                ready = true; status = target != null ? R.string.waiting_debugging : R.string.waiting;
                                event("local listener ready");
                            }
                        }), records -> main.post(() -> {
                            if (!active || epoch != networkGeneration) { return; }
                            for (LocalMdns.Record record : records) { receive(record); }
                            postPorts();
                        }), () -> remembered ? 10_000 : 2000);
            } catch (java.io.IOException | SecurityException failure) {
                main.post(() -> {
                    if (!active || epoch != networkGeneration) { return; }
                    event("local listener failed"); status = R.string.discovery_failed;
                    // Retry the current interface; a Wi-Fi transition may briefly leave it unusable.
                    bindNetwork(null, null);
                    status = R.string.discovery_failed;
                    main.postDelayed(() -> { if (active) { updateNetwork(); } }, 3000);
                });
            }
        }, "Anmir-local-mdns");
        listener.start();
    }
    private void receive(LocalMdns.Record record) {
        if (!record.pairing) {
            connections.remove(record.name);
            if (record.ttl > 0) { connections.put(record.name, new Connection(record)); }
            return;
        }
        RelaySession candidate = RelaySession.parse(record.name);
        if (candidate == null || record.ttl == 0 || record.name.equals(expiredSession)) { return; }
        if (session == null || !session.name.equals(candidate.name)) {
            session = candidate; sessionStarted = SystemClock.elapsedRealtime(); acceptedReports = 0;
            nextPost = 0; failures = 0; event("local pairing port=" + record.port);
        }
        pairingPort = record.port;
    }
    private void postPorts() {
        if (!active || wifiNetwork == null || posting || (session == null && target == null)) { return; }
        final RelaySession current = session;
        final ReconnectTarget known = current == null ? target : null;
        if (current != null && pairingPort == 0) { return; }
        connections.values().removeIf(connection -> connection.expires <= SystemClock.elapsedRealtime());
        List<Connection> currentConnections = new ArrayList<>(connections.values());
        Collections.reverse(currentConnections);
        StringBuilder fingerprint = new StringBuilder();
        for (Connection value : currentConnections) {
            if (known == null || known.guid.equals(value.name)) { fingerprint.append(value.name).append(':').append(value.port).append(';'); }
        }
        if (!fingerprint.toString().equals(lastPorts)) { nextPost = 0; failures = 0; lastPorts = fingerprint.toString(); }
        if (SystemClock.elapsedRealtime() < nextPost) { return; }
        final boolean forced = known != null && retryRequested;
        if (forced) { retryRequested = false; }
        posting = true;
        final int currentPairingPort = pairingPort, epoch = networkGeneration;
        final Network network = wifiNetwork;
        final Inet4Address address = localAddress;
        if (current != null) { status = acceptedReports > 0 ? R.string.sent : R.string.sending; }
        worker.execute(() -> {
            workerStage = "preparing";
            int response = 0;
            ReconnectTarget issued = null;
            String failure = "";
            boolean hasPorts = false;
            try {
                if (verifiedGeneration != epoch) { verifiedPorts.clear(); verifiedGeneration = epoch; }
                JSONArray services = new JSONArray();
                for (Connection connection : currentConnections) {
                    if (known != null && !known.guid.equals(connection.name)) { continue; }
                    if (services.length() == 8) { break; }
                    long now = SystemClock.elapsedRealtime();
                    if (verifiedPorts.getOrDefault(connection.port, 0L) <= now) {
                        try (Socket socket = new Socket()) {
                            network.bindSocket(socket);
                            socket.connect(new InetSocketAddress(address, connection.port), 250);
                            verifiedPorts.put(connection.port, now + 3000);
                        } catch (java.io.IOException closed) { continue; }
                    }
                    services.put(new JSONObject().put("name", connection.name).put("port", connection.port));
                }
                JSONObject report = new JSONObject().put("connections", services);
                hasPorts = services.length() > 0;
                if (forced) { report.put("retry", true); }
                if (current != null) { report.put("service", current.name).put("pairingPort", currentPairingPort); }
                String host = current != null ? current.host : known.host;
                int port = current != null ? current.port : known.port;
                String path = current != null ? "/v1/relay/" + current.token : known.path();
                try (Socket socket = network.getSocketFactory().createSocket()) {
                    workerStage = "callback";
                    socket.connect(new InetSocketAddress(host, port), 3000);
                    RelayHttp.Reply reply = RelayHttp.post(socket, host, port, path, report.toString().getBytes(StandardCharsets.UTF_8));
                    response = reply.status;
                    if (response == 201 && current != null) {
                        JSONObject config = new JSONObject(reply.body).getJSONObject("reconnect");
                        // The Mac may rotate credentials, but cannot redirect this bootstrap to a different address or port.
                        issued = ReconnectTarget.create(current.host, config.getInt("port"), config.getString("token"), config.getString("guid"));
                        if (issued == null || issued.port != current.port) { throw new java.io.IOException("Invalid registration"); }
                    }
                }
            } catch (java.io.IOException | org.json.JSONException error) { failure = error.getClass().getSimpleName(); }
            final int code = response;
            final ReconnectTarget registration = issued;
            final String reason = failure;
            final boolean advertised = hasPorts;
            workerStage = "idle";
            main.post(() -> {
                posting = false;
                if (forced) { retrying = false; }
                if (!active || epoch != networkGeneration || session != current || (current == null && target != known)) { return; }
                event("callback response=" + code + (reason.isEmpty() ? "" : " " + reason));
                if (code == 201 && registration != null && saveTarget(registration)) {
                    target = registration; remembered = true;
                    expiredSession = current.name; session = null; pairingPort = 0;
                    main.removeCallbacks(deadline); failures = 0; nextPost = 0;
                    status = R.string.reconnect_enabled; postPorts(); return;
                }
                boolean success = code == 202;
                if (success) { ++acceptedReports; failures = 0; }
                nextPost = SystemClock.elapsedRealtime() + (success ? current != null ? 2000 : 15_000
                        : ReconnectTarget.retryDelay(failures++));
                if (known != null) {
                    status = code == 404 || code == 410 ? R.string.reconnect_rescan
                            : success ? advertised ? R.string.reconnect_enabled : R.string.waiting_debugging
                            : R.string.reconnect_retry;
                } else if (code == 410) {
                    expiredSession = current.name; session = null; pairingPort = 0;
                    status = target != null ? R.string.reconnect_enabled : R.string.expired;
                } else { status = success || acceptedReports > 0 ? R.string.sent : R.string.failed; }
                if (retryRequested) { nextPost = 0; postPorts(); }
            });
        });
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && "stop".equals(intent.getAction())) { stopSelf(); }
        else if (intent != null && "retry".equals(intent.getAction()) && target != null) {
            retryRequested = true; nextPost = 0; failures = 0; retrying = wifiNetwork != null;
            status = wifiNetwork == null ? R.string.waiting_wifi : R.string.retry_requesting;
            postPorts();
        }
        else if (intent != null && "forget".equals(intent.getAction())) {
            preferences().edit().remove("mac").apply(); target = null; remembered = false;
            nextPost = 0; lastPorts = ""; status = wifiNetwork == null ? R.string.waiting_wifi : R.string.waiting;
            main.removeCallbacks(deadline); main.postDelayed(deadline, 5 * 60_000);
        } else if (target == null) {
            main.removeCallbacks(deadline); main.postDelayed(deadline, 5 * 60_000);
        }
        return START_NOT_STICKY;
    }
    @Override protected void dump(FileDescriptor fd, PrintWriter out, String[] args) {
        out.println("active=" + active + " localConnectionServices=" + connections.size()
                + " pairingService=" + (session != null) + " acceptedReports=" + acceptedReports
                + " ready=" + ready + " remembered=" + remembered + " networkGeneration=" + networkGeneration);
        out.println("packets=" + mdnsStats.packets + " ownPackets=" + mdnsStats.ownPackets + " records=" + mdnsStats.records);
        out.println("posting=" + posting + " stage=" + workerStage + " retries=" + failures);
        for (String value : events) { out.println(value); }
    }
    @Override public void onDestroy() {
        active = false; ++networkGeneration; running = ready = retrying = false;
        main.removeCallbacksAndMessages(null);
        if (callbackRegistered) { connectivity.unregisterNetworkCallback(networkCallback); }
        if (listener != null) { listener.interrupt(); }
        if (multicastLock != null && multicastLock.isHeld()) { multicastLock.release(); }
        worker.shutdownNow(); session = null; connections.clear();
        if (status != R.string.discovery_failed && status != R.string.wifi_required) { status = R.string.stopped; }
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
