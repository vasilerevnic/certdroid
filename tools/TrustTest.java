import java.net.*;
import java.io.*;
import java.security.cert.*;
import java.util.*;
import javax.net.ssl.*;

public class TrustTest {
  public static void main(String[] args) {
    HttpsURLConnection connection = null;
    try {
      if (args.length != 4) throw new IllegalArgumentException("TrustTest <proxy-host> <port> <https-url> <expected-ca.pem>");
      int port = Integer.parseInt(args[1]);
      if (port < 1 || port > 65535) throw new IllegalArgumentException("Port out of range");
      URL url = new URL(args[2]);
      if (!"https".equalsIgnoreCase(url.getProtocol())) throw new IllegalArgumentException("HTTPS URL required");
      X509Certificate expected;
      try (InputStream in = new FileInputStream(args[3])) {
        expected = (X509Certificate) CertificateFactory.getInstance("X.509").generateCertificate(in);
      }
      expected.checkValidity();
      if (expected.getBasicConstraints() < 0) throw new CertificateException("Expected certificate is not a CA");
      Proxy proxy = new Proxy(Proxy.Type.HTTP, new InetSocketAddress(args[0], port));
      connection = (HttpsURLConnection) url.openConnection(proxy);
      connection.setConnectTimeout(10000);
      connection.setReadTimeout(10000);
      connection.setInstanceFollowRedirects(false);
      // Use the platform's default trust manager and hostname verifier.
      int code = connection.getResponseCode();
      java.security.cert.Certificate[] peer = connection.getServerCertificates();
      List<X509Certificate> chain = new ArrayList<X509Certificate>();
      for (java.security.cert.Certificate certificate : peer) chain.add((X509Certificate) certificate);
      X509Certificate leaf = chain.get(0);
      // Build a second path anchored ONLY in the supplied CA. An issuer name
      // comparison cannot distinguish teammates' CAs with identical subjects.
      X509CertSelector selector = new X509CertSelector();
      selector.setCertificate(leaf);
      PKIXBuilderParameters parameters = new PKIXBuilderParameters(
          Collections.singleton(new TrustAnchor(expected, null)), selector);
      parameters.setRevocationEnabled(false);
      parameters.addCertStore(CertStore.getInstance("Collection", new CollectionCertStoreParameters(chain)));
      CertPathBuilder.getInstance("PKIX").build(parameters);
      System.out.println("RESULT=TRUSTED http=" + code);
      System.out.println("leaf_subject=" + leaf.getSubjectX500Principal());
      System.out.println("leaf_issuer=" + leaf.getIssuerX500Principal());
    } catch (Exception error) {
      System.err.println("RESULT=FAILED " + error.getClass().getName() + ": " + error.getMessage());
      System.exit(1);
    } finally {
      if (connection != null) connection.disconnect();
    }
  }
}
