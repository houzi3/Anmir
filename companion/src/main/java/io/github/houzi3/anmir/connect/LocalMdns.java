package io.github.houzi3.anmir.connect;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.net.DatagramPacket;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.MulticastSocket;
import java.net.NetworkInterface;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.function.BooleanSupplier;
import java.util.function.Consumer;
import java.util.function.LongSupplier;

/** Reads only this phone's ADB records, independently of framework NSD callbacks. */
final class LocalMdns {
    interface SocketBinder { void bind(java.net.DatagramSocket socket) throws IOException; }
    static final class Stats { volatile int packets; volatile int ownPackets; volatile int records; }
    static byte[] query(String name, int type) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        DataOutputStream out = new DataOutputStream(bytes);
        out.writeShort(0); out.writeShort(0); out.writeShort(1);
        out.writeShort(0); out.writeShort(0); out.writeShort(0);
        for (String label : name.split("\\.")) {
            byte[] value = label.getBytes(StandardCharsets.UTF_8);
            if (value.length == 0 || value.length > 63) { throw new IOException("Invalid DNS label"); }
            out.writeByte(value.length); out.write(value);
        }
        out.writeByte(0); out.writeShort(type); out.writeShort(1);
        return bytes.toByteArray();
    }

    static void listen(Inet4Address local, SocketBinder binder, Stats stats,
            BooleanSupplier running, Runnable ready, Consumer<List<Record>> received) throws IOException {
        listen(local, binder, stats, running, ready, received, () -> 2000);
    }
    static void listen(Inet4Address local, SocketBinder binder, Stats stats,
            BooleanSupplier running, Runnable ready, Consumer<List<Record>> received, LongSupplier queryInterval) throws IOException {
        NetworkInterface network = NetworkInterface.getByInetAddress(local);
        if (network == null) { throw new IOException("No Wi-Fi interface"); }
        InetSocketAddress group = new InetSocketAddress("224.0.0.251", 5353);
        try (MulticastSocket socket = new MulticastSocket(null)) {
            binder.bind(socket);
            socket.setReuseAddress(true);
            socket.bind(new InetSocketAddress(5353));
            socket.setNetworkInterface(network);
            socket.setTimeToLive(255);
            socket.setLoopbackMode(false);
            socket.setSoTimeout(200);
            socket.joinGroup(group, network);
            long nextQuery = 0;
            boolean announced = false;
            while (running.getAsBoolean() && !Thread.currentThread().isInterrupted()) {
                if (System.nanoTime() >= nextQuery) {
                    for (String type : new String[] {"_adb-tls-pairing._tcp.local", "_adb-tls-connect._tcp.local"}) {
                        byte[] query = query(type, 12);
                        // Local responders differ in whether they accept direct unicast.
                        socket.send(new DatagramPacket(query, query.length, local, 5353));
                        socket.send(new DatagramPacket(query, query.length, group));
                    }
                    nextQuery = System.nanoTime() + Math.max(2000, queryInterval.getAsLong()) * 1_000_000L;
                    if (!announced) { announced = true; ready.run(); }
                }
                DatagramPacket response = new DatagramPacket(new byte[9000], 9000);
                try {
                    socket.receive(response);
                    ++stats.packets;
                    if (!response.getAddress().equals(local) || response.getPort() != 5353) { continue; }
                    ++stats.ownPackets;
                    List<Record> records = records(response.getData(), response.getLength());
                    stats.records += records.size();
                    if (!records.isEmpty()) { received.accept(records); }
                } catch (SocketTimeoutException ignored) { }
            }
        }
    }

    static final class Record {
        final String name;
        final boolean pairing;
        final int port;
        final long ttl;
        Record(String name, boolean pairing, int port, long ttl) {
            this.name = name; this.pairing = pairing; this.port = port; this.ttl = ttl;
        }
    }

    private static int u16(byte[] bytes, int at, int length) throws IOException {
        if (at < 0 || at + 2 > length) { throw new IOException("Short DNS packet"); }
        return ((bytes[at] & 255) << 8) | (bytes[at + 1] & 255);
    }

    private static final class Name {
        final String value;
        final int next;
        Name(String value, int next) { this.value = value; this.next = next; }
    }

    private static Name name(byte[] bytes, int at, int length) throws IOException {
        StringBuilder value = new StringBuilder();
        int next = -1;
        for (int hops = 0; hops < 128; ++hops) {
            if (at < 0 || at >= length) { throw new IOException("Short DNS name"); }
            int size = bytes[at] & 255;
            if ((size & 0xc0) == 0xc0) {
                int pointer = u16(bytes, at, length) & 0x3fff;
                if (next < 0) { next = at + 2; }
                at = pointer;
            } else if (size == 0) {
                return new Name(value.toString(), next < 0 ? at + 1 : next);
            } else {
                if (size > 63 || at + 1 + size > length || value.length() + size > 253) {
                    throw new IOException("Invalid DNS name");
                }
                if (value.length() != 0) { value.append('.'); }
                value.append(new String(bytes, at + 1, size, StandardCharsets.UTF_8));
                at += 1 + size;
            }
        }
        throw new IOException("DNS pointer loop");
    }

    static List<Record> records(byte[] bytes, int length) {
        List<Record> result = new ArrayList<>();
        try {
            if (length < 12 || length > bytes.length || (u16(bytes, 2, length) & 0xf80f) != 0x8000) { return result; }
            int questions = u16(bytes, 4, length);
            int records = u16(bytes, 6, length) + u16(bytes, 8, length) + u16(bytes, 10, length);
            if (questions > 64 || records > 256) { return result; }
            int at = 12;
            for (int i = 0; i < questions; ++i) {
                at = name(bytes, at, length).next + 4;
                if (at > length) { throw new IOException("Short DNS question"); }
            }
            for (int i = 0; i < records; ++i) {
                Name owner = name(bytes, at, length);
                at = owner.next;
                int type = u16(bytes, at, length);
                int dnsClass = u16(bytes, at + 2, length) & 0x7fff;
                int size = u16(bytes, at + 8, length);
                if (at + 10 + size > length) { throw new IOException("Short DNS record"); }
                long ttl = ((long) u16(bytes, at + 4, length) << 16) | u16(bytes, at + 6, length);
                at += 10;
                String lower = owner.value.toLowerCase(java.util.Locale.ROOT);
                String pairing = "._adb-tls-pairing._tcp.local";
                String connect = "._adb-tls-connect._tcp.local";
                String suffix = lower.endsWith(pairing) ? pairing : lower.endsWith(connect) ? connect : null;
                if (type == 33 && dnsClass == 1 && size >= 7 && suffix != null) {
                    int port = u16(bytes, at + 4, length);
                    if (name(bytes, at + 6, length).next <= at + size && port > 0) {
                        result.add(new Record(owner.value.substring(0, owner.value.length() - suffix.length()),
                                suffix.equals(pairing), port, ttl));
                    }
                }
                at += size;
            }
        } catch (IOException ignored) { result.clear(); }
        return result;
    }
}
