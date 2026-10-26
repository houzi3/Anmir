package io.github.houzi3.anmir.connect;

import java.util.regex.Pattern;

/** Durable callback credentials, issued only after the Mac verifies ADB pairing. */
final class ReconnectTarget {
    final String host, token, guid;
    final int port;
    private ReconnectTarget(String host, int port, String token, String guid) {
        this.host = host; this.port = port; this.token = token; this.guid = guid;
    }
    static ReconnectTarget create(String host, int port, String token, String guid) {
        if (host == null || token == null || guid == null || port < 1 || port > 65535
                || !Pattern.matches("[0-9a-f]{32}", token)
                || !Pattern.matches("[a-zA-Z0-9_.-]{1,255}", guid)) { return null; }
        String[] octets = host.split("\\.", -1);
        if (octets.length != 4) { return null; }
        for (int i = 0; i < 4; ++i) {
            if (!octets[i].matches("0|[1-9][0-9]{0,2}")) { return null; }
            int value = Integer.parseInt(octets[i]);
            if (value > 255 || (i == 0 && (value == 0 || value == 127 || value >= 224))) { return null; }
        }
        return new ReconnectTarget(host, port, token, guid);
    }
    static long retryDelay(int failures) { return Math.min(30_000L, 2000L << Math.min(Math.max(failures, 0), 4)); }
    String path() { return "/v1/reconnect/" + token; }
}
