package io.github.houzi3.anmir.connect;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** The DNS instance name carries a callback address, never the ADB pairing secret. */
final class RelaySession {
    private static final Pattern NAME = Pattern.compile(
            "studio-anmir1-([0-9a-f]{8})-([0-9a-f]{4})-([0-9a-f]{32})");
    final String name;
    final String host;
    final int port;
    final String token;

    private RelaySession(String name, String host, int port, String token) {
        this.name = name;
        this.host = host;
        this.port = port;
        this.token = token;
    }

    static RelaySession parse(String name) {
        Matcher match = NAME.matcher(name);
        if (!match.matches()) {
            return null;
        }
        long address = Long.parseLong(match.group(1), 16);
        int first = (int) (address >>> 24);
        int port = Integer.parseInt(match.group(2), 16);
        if (first == 0 || first == 127 || first >= 224 || port == 0) {
            return null;
        }
        String host = String.format(Locale.ROOT, "%d.%d.%d.%d", first,
                (address >>> 16) & 255, (address >>> 8) & 255, address & 255);
        return new RelaySession(name, host, port, match.group(3));
    }

    String url() {
        return "http://" + host + ":" + port + "/v1/relay/" + token;
    }

    static String connectionGuid(String name) {
        // Android's mDNS conflict resolution can append " (2)" to the instance;
        // ADB pairing still returns the original persistent GUID.
        return name.replaceFirst(" \\([1-9][0-9]*\\)$", "");
    }
}
