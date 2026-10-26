package io.github.houzi3.anmir.connect;

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.util.Arrays;
import java.util.List;

public final class LocalMdnsTest {
    private static void label(DataOutputStream out, String value) throws Exception {
        byte[] bytes = value.getBytes("UTF-8");
        out.writeByte(bytes.length); out.write(bytes);
    }

    public static void main(String[] args) throws Exception {
        String type = "_adb-tls-pairing._tcp.local";
        byte[] question = LocalMdns.query(type, 12);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        DataOutputStream out = new DataOutputStream(bytes);
        out.writeShort(0); out.writeShort(0x8400); out.writeShort(1);
        out.writeShort(1); out.writeShort(0); out.writeShort(0);
        out.write(question, 12, question.length - 12);
        label(out, "studio-test"); out.writeShort(0xc00c); // Compressed owner, no TXT record.
        out.writeShort(33); out.writeShort(0x8001); out.writeInt(120);
        out.writeShort(15); out.writeShort(0); out.writeShort(0); out.writeShort(42187);
        label(out, "p"); label(out, "local"); out.writeByte(0);
        byte[] packet = bytes.toByteArray();
        List<LocalMdns.Record> records = LocalMdns.records(packet, packet.length);
        assert records.size() == 1;
        assert records.get(0).name.equals("studio-test");
        assert records.get(0).pairing && records.get(0).port == 42187 && records.get(0).ttl == 120;
        for (int length = 0; length < packet.length; ++length) {
            assert LocalMdns.records(packet, length).isEmpty();
        }
        byte[] loop = new byte[24];
        loop[2] = (byte) 0x84; loop[7] = 1; loop[12] = (byte) 0xc0; loop[13] = 12;
        assert LocalMdns.records(loop, loop.length).isEmpty();
        byte[] query = LocalMdns.query(type, 33);
        assert LocalMdns.records(query, query.length).isEmpty();
        byte[] badClass = packet.clone();
        int header = question.length + 12 + 2;
        badClass[header + 3] = 2;
        assert LocalMdns.records(badClass, badClass.length).isEmpty();
        System.out.println("Local mDNS compressed SRV, missing TXT, truncated packets and pointer-loop checks passed.");
    }
}
