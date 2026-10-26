package io.github.houzi3.anmir.connect;

import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

public final class ReconnectTest {
    private static RelayHttp.Reply exchange(String response) throws Exception {
        try (ServerSocket server = new ServerSocket(0)) {
            Thread worker = new Thread(() -> {
                try (Socket peer = server.accept()) {
                    // Consume the complete request before replying.
                    int end = 0;
                    while (end != 4) {
                        int value = peer.getInputStream().read();
                        if (value == -1) { return; }
                        end = value == (end % 2 == 0 ? '\r' : '\n') ? end + 1 : 0;
                    }
                    peer.getInputStream().read(); peer.getInputStream().read();
                    peer.getOutputStream().write(response.getBytes(StandardCharsets.US_ASCII));
                } catch (Exception error) { throw new RuntimeException(error); }
            });
            worker.start();
            try (Socket client = new Socket("127.0.0.1", server.getLocalPort())) {
                return RelayHttp.post(client, "127.0.0.1", server.getLocalPort(), "/test", new byte[]{'{', '}'});
            } finally { worker.join(4000); assert !worker.isAlive(); }
        }
    }
    public static void main(String[] args) throws Exception {
        String token = "0123456789abcdef0123456789abcdef";
        ReconnectTarget valid = ReconnectTarget.create("192.0.2.69", 37899, token, "adb-phone");
        assert valid != null && valid.path().equals("/v1/reconnect/" + token);
        for (String host : new String[]{"127.0.0.1", "0.1.2.3", "224.0.0.251", "1.2.3.256", "10.01.2.3", "example.com", "::1", "1.2.3.4\r\n"}) {
            assert ReconnectTarget.create(host, 37899, token, "adb-phone") == null : host;
        }
        assert ReconnectTarget.create(valid.host, 0, token, valid.guid) == null;
        assert ReconnectTarget.create(valid.host, 65536, token, valid.guid) == null;
        assert ReconnectTarget.create(valid.host, valid.port, token + "x", valid.guid) == null;
        assert ReconnectTarget.create(valid.host, valid.port, token, "other/host") == null;
        assert ReconnectTarget.retryDelay(0) == 2000 && ReconnectTarget.retryDelay(1) == 4000;
        assert ReconnectTarget.retryDelay(4) == 30000 && ReconnectTarget.retryDelay(1000) == 30000;
        RelayHttp.Reply reply = exchange("HTTP/1.1 201 Accepted\r\nContent-Length: 2\r\n\r\n{}");
        assert reply.status == 201 && reply.body.equals("{}");
        assert exchange("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\n\r\n").status == 202;
        for (String bad : new String[]{"HTTP/1.1 201 Accepted\r\nContent-Length: 99999\r\n\r\n",
                "HTTP/1.1 201 Accepted\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}",
                "HTTP/1.1 201 Accepted\r\nTransfer-Encoding: chunked\r\n\r\n",
                "HTTP/1.1 201 Accepted\r\nContent-Length: 2\r\n\r\n{"}) {
            try { exchange(bad); throw new AssertionError("Invalid reply accepted"); }
            catch (java.io.IOException expected) { }
        }
        System.out.println("Reconnect credentials, bounded backoff and HTTP handoff passed.");
    }
}
