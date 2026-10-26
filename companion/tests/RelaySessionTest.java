package io.github.houzi3.anmir.connect;

public final class RelaySessionTest {
    public static void main(String[] args) {
        String token = "0123456789abcdef0123456789abcdef";
        String name = "studio-anmir1-c000020a-a123-" + token;
        RelaySession session = RelaySession.parse(name);
        assert session != null;
        assert session.host.equals("192.0.2.10");
        assert session.port == 41251;
        assert session.url().equals("http://192.0.2.10:41251/v1/relay/" + token);
        assert RelaySession.connectionGuid("adb-phone (2)").equals("adb-phone");
        assert RelaySession.connectionGuid("adb-phone (12)").equals("adb-phone");
        assert RelaySession.connectionGuid("adb-phone").equals("adb-phone");
        assert RelaySession.connectionGuid("adb-other").equals("adb-other");
        for (String invalid : new String[] {"studio-normal", name + "x", name.substring(1),
                name.replace("-a123-", "-0000-"), name.replace("c000020a", "7f000001"),
                name.replace("c000020a", "e00000fb"), name.replace("c000020a", "00000000"),
                name.replace("c000020a", "zzzzzzzz")}) {
            assert RelaySession.parse(invalid) == null : invalid;
        }
        System.out.println("Relay session address, callback and invalid QR names passed.");
    }
}
