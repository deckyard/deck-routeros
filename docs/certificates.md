# Certificates

File: `src/topics/certificates.j`. Path: `/certificate`
(`CERTIFICATE_PATH`).
Reference: [cheatsheet](cheatsheet.md#certificates).

The certificate store backs every TLS service on the router: the secure
API (`api-ssl`), WebFig over HTTPS (`www-ssl`), SSTP and OpenVPN servers.
An SSL service without a certificate shows as `invalid` in
[services.md](services.md). Three ways to get one:

1. `enableLetsEncrypt`: RouterOS v7 obtains and renews a Let's Encrypt
   certificate itself (http-01). Port 80 must be reachable from the
   internet under the DNS name; [cloud.md](cloud.md) provides one.
2. `importCertificatePem`: a certificate from your CA, or from the
   Jennifer `acme` module when the router is behind NAT.
3. `generateSelfSigned`: LAN-only services whose clients trust it
   manually. Validity 1-7300 days.

All of them need a correct clock. A router that booted without NTP
rejects every certificate; set up [clock.md](clock.md) first.

```jennifer
# self-signed TLS for the API, LAN only
mt.generateSelfSigned($c, "router-lan", "router.lan", 1095);
mt.assignServiceCertificate($c, "api-ssl", "router-lan");
mt.restrictService($c, "api-ssl", "10.0.9.0/24");
# from now on connect with mt.connectTLS(...)

# Let's Encrypt on an internet-reachable router
mt.enableCloudDns($c);
def name as string init mt.routerDnsName($c);
mt.enableLetsEncrypt($c, $name);      # blocks while the challenge runs
mt.assignServiceCertificate($c, "www-ssl", $name);

# renewal audit
def soon as list of mt.Certificate init mt.expiringCertificates($c, 30);
for (def cert in $soon) {
    io.printf("renew: %s (%s) expires in %s\n",
        $cert.name, $cert.commonName, $cert.expiresAfter);
}
```

`expiringCertificates` reads `expiresAfter` (`"51w6d"`, `"4w2d13h"`),
rounds down to whole days and skips certificates whose expiry is missing
or does not parse.

## Behind NAT: the Jennifer `acme` module

The Jennifer host obtains the certificate (dns-01 with your DNS provider,
or http-01 served by the host) and pushes it in:

```jennifer
use crypto;
import "acme.j";
def key as bytes init crypto.ecGenerateKey("p256");
def csr as bytes init crypto.csr($key, "vpn.example.org", []);
# order, challenge, finalize: see the acme module docs; try the staging CA first
# def certPem as string init acme.downloadCertificate($client, $order);
# mt.importCertificatePem($c, "vpn-example-org", $certPem,
#     convert.stringFromBytes($key, "utf-8"));
# mt.assignServiceCertificate($c, "api-ssl", "vpn-example-org");
```

Renewal is host-driven: re-run the flow when `expiringCertificates`
names the certificate. The import writes the PEMs to temporary files
(`<name>.crt`, `<name>.key`) through the API and deletes them afterwards,
so the key crosses the API connection: use `connectTLS`. The `.crt` may
hold the full chain; certificate and key imported under the same name
merge into one entry with `hasPrivateKey` true.
