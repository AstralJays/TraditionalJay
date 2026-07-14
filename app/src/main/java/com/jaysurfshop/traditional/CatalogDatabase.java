package com.jaysurfshop.traditional;

import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Intentionally insecure SQLite catalog for SQL injection workshops.
 */
@Component
public class CatalogDatabase {
  private final Path dbPath;

  public CatalogDatabase() {
    String configured = System.getenv("TRADITIONALJAY_DB");
    this.dbPath = Path.of(
        configured != null && !configured.isBlank()
            ? configured
            : "/tmp/traditionaljay-shop.db"
    );
  }

  @PostConstruct
  public void init() throws Exception {
    Files.createDirectories(dbPath.toAbsolutePath().getParent());
    try (Connection conn = open(); Statement st = conn.createStatement()) {
      st.executeUpdate(
          "CREATE TABLE IF NOT EXISTS products ("
              + "id INTEGER PRIMARY KEY, name TEXT, sku TEXT, price TEXT)"
      );
      st.executeUpdate(
          "CREATE TABLE IF NOT EXISTS secrets ("
              + "id INTEGER PRIMARY KEY, k TEXT, v TEXT)"
      );
      st.executeUpdate("DELETE FROM products");
      st.executeUpdate("DELETE FROM secrets");
      st.executeUpdate("INSERT INTO products(name,sku,price) VALUES "
          + "('Pipeline Pro Shortboard','SB-PP-62','749.99'),"
          + "('Malibu Funboard','FB-MAL-76','599.99'),"
          + "('Classic Longboard','LB-CL-90','899.99'),"
          + "('Tropical Grip Wax','WX-TROP','4.99'),"
          + "('3/2mm Full Suit','WS-32-FULL','189.99')");
      st.executeUpdate("INSERT INTO secrets(k,v) VALUES "
          + "('admin_password','surf-workshop-admin'),"
          + "('db_backup_url','s3://jays-demo-internal/shop-backup.sql'),"
          + "('c2_hint','Use /api/demo/reverse-shell after Log4Shell')");
    }
  }

  public Connection open() throws Exception {
    Class.forName("org.sqlite.JDBC");
    return DriverManager.getConnection("jdbc:sqlite:" + dbPath);
  }

  /** Vulnerable CONCAT — do not copy this pattern. */
  public List<Map<String, String>> searchVulnerable(String q) throws Exception {
    // Intentional SQL injection sink for Critical VM Compromise demos.
    String sql = "SELECT id, name, sku, price FROM products WHERE name LIKE '%"
        + q + "%' OR sku LIKE '%" + q + "%'";
    List<Map<String, String>> rows = new ArrayList<>();
    try (Connection conn = open();
         Statement st = conn.createStatement();
         ResultSet rs = st.executeQuery(sql)) {
      while (rs.next()) {
        Map<String, String> row = new LinkedHashMap<>();
        row.put("id", rs.getString("id"));
        row.put("name", rs.getString("name"));
        row.put("sku", rs.getString("sku"));
        row.put("price", rs.getString("price"));
        rows.add(row);
      }
    }
    return rows;
  }

  public String lastSql(String q) {
    return "SELECT id, name, sku, price FROM products WHERE name LIKE '%"
        + q + "%' OR sku LIKE '%" + q + "%'";
  }

  public Path getDbPath() {
    return dbPath;
  }
}
