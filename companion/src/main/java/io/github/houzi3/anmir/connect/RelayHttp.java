package io.github.houzi3.anmir.connect;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

/** Small bounded HTTP exchange: numeric Wi-Fi endpoint, no proxy or redirects. */
final class RelayHttp {
    static final class Reply {
        final int status;
        final String body;
        Reply(int status, String body) { this.status = status; this.body = body; }
    }
    private static String line(InputStream input, long deadline, int limit) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        while (System.nanoTime() < deadline && bytes.size() < limit) {
            int value = input.read();
            if (value == -1) { throw new IOException("Short HTTP response"); }
            if (value == '\n') { return bytes.toString("US-ASCII").trim(); }
            bytes.write(value);
        }
        throw new IOException("HTTP response limit");
    }
    static Reply post(Socket socket, String host, int port, String path, byte[] body) throws IOException {
        socket.setSoTimeout(3000);
        String header = "POST " + path + " HTTP/1.1\r\nHost: " + host + ":" + port
                + "\r\nContent-Type: application/json\r\nContent-Length: " + body.length
                + "\r\nConnection: close\r\n\r\n";
        OutputStream out = socket.getOutputStream();
        out.write(header.getBytes(StandardCharsets.US_ASCII)); out.write(body); out.flush();
        InputStream input = socket.getInputStream();
        long deadline = System.nanoTime() + 3_000_000_000L;
        String[] status = line(input, deadline, 512).split(" ", 3);
        if (status.length < 2 || !status[0].equals("HTTP/1.1")) { throw new IOException("Invalid HTTP status"); }
        int code;
        try { code = Integer.parseInt(status[1]); }
        catch (NumberFormatException invalid) { throw new IOException("Invalid HTTP status"); }
        int length = -1, read = 0;
        String value;
        while (!(value = line(input, deadline, 1024)).isEmpty()) {
            read += value.length();
            if (read > 4096 || value.toLowerCase(java.util.Locale.ROOT).startsWith("transfer-encoding:")) {
                throw new IOException("Invalid HTTP headers");
            }
            if (value.toLowerCase(java.util.Locale.ROOT).startsWith("content-length:")) {
                if (length != -1) { throw new IOException("Duplicate HTTP length"); }
                try { length = Integer.parseInt(value.substring(15).trim()); }
                catch (NumberFormatException invalid) { throw new IOException("Invalid HTTP length"); }
                if (length < 0 || length > 2048) { throw new IOException("HTTP body limit"); }
            }
        }
        if (length == -1) { throw new IOException("Missing HTTP length"); }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        while (bytes.size() < length && System.nanoTime() < deadline) {
            int next = input.read();
            if (next == -1) { throw new IOException("Short HTTP body"); }
            bytes.write(next);
        }
        if (bytes.size() != length) { throw new IOException("HTTP body timeout"); }
        return new Reply(code, bytes.toString("UTF-8"));
    }
}
