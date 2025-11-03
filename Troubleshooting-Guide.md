# Nexus Sandbox Framework - Comprehensive Troubleshooting Guide

## Table of Contents

1. [Pre-Deployment Troubleshooting](#pre-deployment-troubleshooting)
2. [OpenTofu/Terraform Issues](#opentofuterraform-issues)
3. [Proxmox-Specific Issues](#proxmox-specific-issues)
4. [Networking Issues](#networking-issues)
5. [K3s Installation Issues](#k3s-installation-issues)
6. [Kata Containers Issues](#kata-containers-issues)
7. [GPU Passthrough Issues](#gpu-passthrough-issues)
8. [Kubernetes Runtime Issues](#kubernetes-runtime-issues)
9. [RBaaS Deployment Issues](#rbaas-deployment-issues)
10. [Observability Stack Issues](#observability-stack-issues)
11. [Common Error Messages](#common-error-messages)
12. [Performance Debugging](#performance-debugging)
13. [Recovery Procedures](#recovery-procedures)

---

## Pre-Deployment Troubleshooting

### Issue: Preflight checks failing

**Symptoms:**
```
ERROR: Proxmox API endpoint unreachable
ERROR: API credentials invalid
```

**Diagnosis:**
```bash
# Test Proxmox connectivity
curl -k https://your-proxmox-host:8006/api2/json/version

# Verify API token
curl -k -H "Authorization: PVEAPIToken=USER@REALM!TOKENID=SECRET" \
  https://your-proxmox-host:8006/api2/json/cluster/resources
```

**Solutions:**
1. **Check firewall rules:**
   ```bash
   # On Proxmox host
   iptables -L -n | grep 8006
   ufw status
   ```

2. **Verify API token permissions:**
   - Log into Proxmox web UI
   - Navigate to: Datacenter → Permissions → API Tokens
   - Ensure token has `PVEAdmin` or `Administrator` role

3. **Check certificate issues:**
   ```bash
   # Update deployment_config.yaml
   proxmox:
     verify_ssl: false  # For self-signed certs
   ```

### Issue: SSH key not found

**Symptoms:**
```
ERROR: SSH public key file not found: ~/.ssh/id_rsa.pub
```

**Solutions:**
```bash
# Generate new SSH key pair
ssh-keygen -t ed25519 -C "nexus-deployment" -f ~/.ssh/id_ed25519 -N ""

# Update deployment_config.yaml
vms:
  ssh_key_file: "~/.ssh/id_ed25519.pub"
```

### Issue: Insufficient Proxmox resources

**Symptoms:**
```
ERROR: Not enough CPU/memory/storage on Proxmox node
```

**Diagnosis:**
```bash
# Check available resources
pvesh get /nodes/pve/status
pvesh get /nodes/pve/storage/local-zfs/status
```

**Solutions:**
1. Reduce VM counts in `deployment_config.yaml`:
   ```yaml
   vms:
     control_plane:
       count: 1  # Minimum for testing
     workers:
       count: 1
     gpu_workers:
       count: 0  # Disable if no GPU
   ```

---

## OpenTofu/Terraform Issues

### Issue: Provider plugin download fails

**Symptoms:**
```
Error: Failed to install provider
Error: Failed to query available provider packages
```

**Solutions:**
```bash
# Clear provider cache
rm -rf .terraform/
rm -f .terraform.lock.hcl

# Re-initialize with verbose logging
export TF_LOG=DEBUG
tofu init

# Alternative: Use mirror
tofu init -plugin-dir=/usr/local/share/terraform/plugins
```

### Issue: State lock timeout

**Symptoms:**
```
Error: Error acquiring the state lock
Error: Backend initialization failed: timeout
```

**Solutions:**
```bash
# Force unlock (USE WITH CAUTION)
tofu force-unlock <LOCK_ID>

# If using local state, check for zombie processes
ps aux | grep terraform
kill -9 <PID>

# Remove lock file (local backend only)
rm -f terraform.tfstate.lock.info
```

### Issue: API rate limiting

**Symptoms:**
```
Error: Provider produced inconsistent result after apply
Error: timeout waiting for state to become 'running'
```

**Solutions:**
```bash
# Add delays between resource creation
# In main.tf, add:
resource "time_sleep" "wait_30_seconds" {
  depends_on = [proxmox_virtual_environment_vm.control_plane]
  create_duration = "30s"
}

# Reduce parallelism
tofu apply -parallelism=1
```

---

## Proxmox-Specific Issues

### Issue: Cloud-init template missing

**Symptoms:**
```
Error: VM template 'ubuntu-2204-cloudinit-template' not found
```

**Solutions:**
```bash
# Create Ubuntu 22.04 cloud-init template
cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Create VM template
qm create 9000 --name ubuntu-2204-cloudinit-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-zfs
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-zfs:vm-9000-disk-0
qm set 9000 --ide2 local:cloudinit
qm set 9000 --boot c --bootdisk scsi0
qm set 9000 --serial0 socket --vga serial0
qm set 9000 --agent enabled=1

# Convert to template
qm template 9000
```

### Issue: Nested virtualization not enabled

**Symptoms:**
```
ERROR: KVM hardware virtualization not available
ERROR: /dev/kvm does not exist
```

**Diagnosis:**
```bash
# On Proxmox host
cat /sys/module/kvm_intel/parameters/nested  # Intel
cat /sys/module/kvm_amd/parameters/nested    # AMD
```

**Solutions:**
```bash
# Enable nested virtualization (Intel)
echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm-intel.conf
modprobe -r kvm_intel
modprobe kvm_intel

# Enable nested virtualization (AMD)
echo "options kvm_amd nested=1" > /etc/modprobe.d/kvm-amd.conf
modprobe -r kvm_amd
modprobe kvm_amd

# Verify
cat /sys/module/kvm_*/parameters/nested  # Should show 'Y' or '1'

# Reboot VMs after enabling
```

### Issue: GPU passthrough not working

**Symptoms:**
```
ERROR: vfio-pci driver not loaded
ERROR: IOMMU not enabled
```

**Diagnosis:**
```bash
# Check IOMMU status
dmesg | grep -e DMAR -e IOMMU

# List PCI devices
lspci -nn | grep -i nvidia

# Check IOMMU groups
find /sys/kernel/iommu_groups/ -type l
```

**Solutions:**
```bash
# 1. Enable IOMMU in GRUB
vim /etc/default/grub

# For Intel:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"

# For AMD:
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"

update-grub
reboot

# 2. Load VFIO modules
echo "vfio" >> /etc/modules
echo "vfio_iommu_type1" >> /etc/modules
echo "vfio_pci" >> /etc/modules
echo "vfio_virqfd" >> /etc/modules

# 3. Blacklist GPU drivers on host
echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
echo "blacklist nvidia" >> /etc/modprobe.d/blacklist.conf
update-initramfs -u -k all

reboot

# 4. Verify VFIO binding
lspci -nnk | grep -A3 -i nvidia
# Should show: Kernel driver in use: vfio-pci
```

---

## Networking Issues

### Issue: VMs not getting IP addresses

**Symptoms:**
```
ERROR: Timeout waiting for VM to get IP
ERROR: cloud-init failed to configure network
```

**Diagnosis:**
```bash
# Check VM console
qm terminal <VMID>

# Check cloud-init status on VM
cloud-init status --long

# Check network configuration
ip addr show
ip route show
```

**Solutions:**
```bash
# 1. Verify bridge configuration on Proxmox
ip link show vmbr0
brctl show

# 2. Check DHCP server (if using DHCP)
systemctl status dnsmasq

# 3. Manually configure network on VM
# /etc/netplan/50-cloud-init.yaml
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: false
      addresses: [192.168.100.10/24]
      gateway4: 192.168.100.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]

netplan apply
```

### Issue: Cannot reach VMs from external network

**Symptoms:**
```
ERROR: Cannot SSH to VM from deployment machine
ERROR: Connection timeout
```

**Solutions:**
```bash
# 1. Check routing on Proxmox host
ip route show

# 2. Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# 3. Configure NAT (if VMs on private network)
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o vmbr0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

# 4. Add firewall rules
iptables -A FORWARD -i vmbr1 -o vmbr0 -j ACCEPT
iptables -A FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

---

## K3s Installation Issues

### Issue: K3s server fails to start

**Symptoms:**
```
ERROR: Failed to start k3s service
ERROR: etcd cluster not healthy
```

**Diagnosis:**
```bash
# Check K3s logs
journalctl -u k3s -f

# Check systemd status
systemctl status k3s

# Check for port conflicts
netstat -tulpn | grep -E '6443|10250|2379|2380'
```

**Solutions:**
```bash
# 1. Clean previous installation
/usr/local/bin/k3s-killall.sh
/usr/local/bin/k3s-uninstall.sh

# 2. Check for conflicting services
systemctl stop containerd
systemctl disable containerd

# 3. Verify kernel modules
modprobe overlay
modprobe br_netfilter

# 4. Check disk space
df -h /var/lib/rancher

# 5. Re-run installation with debug mode
curl -sfL https://get.k3s.io | K3S_TOKEN=<token> sh -s - --debug
```

### Issue: Worker nodes not joining cluster

**Symptoms:**
```
ERROR: Node not registering with cluster
ERROR: TLS handshake timeout
```

**Diagnosis:**
```bash
# On worker node
journalctl -u k3s-agent -f

# Check connectivity to server
curl -k https://<CONTROL_PLANE_IP>:6443

# Verify token
cat /var/lib/rancher/k3s/server/node-token  # On control plane
```

**Solutions:**
```bash
# 1. Verify firewall rules
# On control plane
ufw allow 6443/tcp  # API server
ufw allow 10250/tcp # Kubelet
ufw allow 2379:2380/tcp # etcd

# 2. Re-generate join token
k3s token create --ttl 24h

# 3. Re-join with correct parameters
curl -sfL https://get.k3s.io | K3S_URL=https://<CONTROL_PLANE_IP>:6443 \
  K3S_TOKEN=<TOKEN> sh -s -

# 4. Check time synchronization
timedatectl status
# Install NTP if needed
apt-get install -y chrony
```

---

## Kata Containers Issues

### Issue: Kata runtime not detected by Kubernetes

**Symptoms:**
```
ERROR: RuntimeClass 'kata' not available
ERROR: Failed to create pod: unknown runtime handler
```

**Diagnosis:**
```bash
# Check if Kata is installed
kata-runtime --version

# Check containerd configuration
cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml

# List available runtimes
crictl info | grep -A 20 runtimes
```

**Solutions:**
```bash
# 1. Install Kata Containers properly
kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-rbac/base/kata-rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-deploy/base/kata-deploy.yaml

# 2. Wait for DaemonSet to complete
kubectl -n kube-system rollout status daemonset/kata-deploy

# 3. Verify kata-deploy logs
kubectl -n kube-system logs -l name=kata-deploy

# 4. Create RuntimeClass manually if needed
cat <<EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata
handler: kata
EOF

# 5. Test Kata pod
kubectl run kata-test --image=nginx --restart=Never --overrides='{"spec":{"runtimeClassName":"kata"}}'
kubectl get pod kata-test -o jsonpath='{.spec.runtimeClassName}'
```

### Issue: Kata VM fails to boot

**Symptoms:**
```
ERROR: Failed to create sandbox
ERROR: timeout waiting for VM to boot
```

**Diagnosis:**
```bash
# Check kata-runtime logs
journalctl -xe | grep kata

# Check for KVM
ls -la /dev/kvm
lsmod | grep kvm

# Test Kata manually
kata-runtime check

# Get detailed Kata config
kata-runtime kata-env
```

**Solutions:**
```bash
# 1. Verify nested virtualization (on worker nodes)
egrep -c '(vmx|svm)' /proc/cpuinfo  # Should be > 0

# 2. Check KVM permissions
chmod 666 /dev/kvm
chown root:kvm /dev/kvm

# 3. Configure Kata hypervisor
mkdir -p /etc/kata-containers/
cat > /etc/kata-containers/configuration.toml <<EOF
[hypervisor.qemu]
path = "/usr/bin/qemu-system-x86_64"
kernel = "/usr/share/kata-containers/vmlinuz.container"
image = "/usr/share/kata-containers/kata-containers.img"
machine_type = "q35"
default_vcpus = 1
default_memory = 2048
enable_debug = true
EOF

# 4. Restart containerd
systemctl restart k3s-agent
```

---

## GPU Passthrough Issues

### Issue: GPU not visible in Kata VM

**Symptoms:**
```
ERROR: nvidia-smi: command not found (inside pod)
ERROR: No NVIDIA GPU detected
```

**Diagnosis:**
```bash
# On GPU worker node
lspci | grep -i nvidia

# Check VFIO binding
lspci -nnk -d 10de:

# In Kata pod (exec into it)
ls /dev/nvidia*
```

**Solutions:**
```bash
# 1. Verify GPU Operator installation
kubectl get pods -n nvidia-gpu-operator

# 2. Check sandbox device plugin
kubectl logs -n nvidia-gpu-operator -l app=nvidia-sandbox-device-plugin

# 3. Reinstall GPU Operator with Kata support
helm uninstall gpu-operator -n nvidia-gpu-operator
helm install gpu-operator nvidia/gpu-operator \
  --namespace nvidia-gpu-operator \
  --create-namespace \
  --set operator.defaultRuntime=kata \
  --set sandbox.enabled=true \
  --set driver.enabled=false \
  --set toolkit.enabled=true

# 4. Verify node labels
kubectl get nodes --show-labels | grep nvidia

# 5. Test GPU workload
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  runtimeClassName: kata
  containers:
  - name: cuda
    image: nvidia/cuda:11.8.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  restartPolicy: Never
  tolerations:
  - key: nvidia.com/gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
EOF

kubectl logs gpu-test
```

### Issue: GPU driver version mismatch

**Symptoms:**
```
ERROR: CUDA version mismatch
ERROR: Driver/library version mismatch
```

**Solutions:**
```bash
# On GPU worker node
nvidia-smi  # Note driver version

# Update GPU Operator to match
helm upgrade gpu-operator nvidia/gpu-operator \
  --set driver.version=<DRIVER_VERSION> \
  --reuse-values

# Or rebuild Kata images with matching CUDA version
```

---

## Kubernetes Runtime Issues

### Issue: Pods stuck in Pending state

**Symptoms:**
```
STATUS: Pending
EVENTS: 0/3 nodes are available: insufficient cpu/memory
```

**Diagnosis:**
```bash
kubectl describe pod <POD_NAME>
kubectl get nodes
kubectl describe node <NODE_NAME>
kubectl top nodes
```

**Solutions:**
```bash
# 1. Check resource quotas
kubectl get resourcequota --all-namespaces

# 2. Check node conditions
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,REASON:.status.conditions[-1].reason

# 3. Increase resources or reduce requests
kubectl edit deployment <DEPLOYMENT_NAME>

# 4. Add more worker nodes (scale infrastructure)
```

### Issue: Pods stuck in ContainerCreating

**Symptoms:**
```
STATUS: ContainerCreating (for > 5 minutes)
EVENTS: Failed to pull image / timeout
```

**Diagnosis:**
```bash
kubectl describe pod <POD_NAME>

# Check runtime
crictl ps -a
crictl logs <CONTAINER_ID>

# Check image pull
crictl images
crictl pull <IMAGE_NAME>
```

**Solutions:**
```bash
# 1. Fix image pull secrets
kubectl create secret docker-registry regcred \
  --docker-server=<REGISTRY> \
  --docker-username=<USER> \
  --docker-password=<PASSWORD>

# 2. Configure insecure registry (if private)
# On each node
vim /etc/rancher/k3s/registries.yaml
mirrors:
  "myregistry.com":
    endpoint:
      - "http://myregistry.com"

systemctl restart k3s-agent

# 3. Pre-pull images
for node in $(kubectl get nodes -o name); do
  ssh $node "crictl pull <IMAGE_NAME>"
done
```

---

## RBaaS Deployment Issues

### Issue: BrowserSession CRD not found

**Symptoms:**
```
ERROR: no matches for kind "BrowserSession"
```

**Solutions:**
```bash
# 1. Verify CRD installation
kubectl get crd browsersessions.rbaas.my-company.com

# 2. Re-apply CRD
kubectl apply -f deploy/crds/browsersession-crd.yaml

# 3. Wait for CRD to be established
kubectl wait --for condition=established --timeout=60s crd/browsersessions.rbaas.my-company.com
```

### Issue: RBaaS Operator not reconciling

**Symptoms:**
```
BrowserSession stuck in "Pending" phase
No pods created for session
```

**Diagnosis:**
```bash
# Check operator logs
kubectl logs -n nexus-system deployment/rbaas-operator -f

# Check operator status
kubectl get deployment -n nexus-system rbaas-operator

# Verify RBAC
kubectl auth can-i create pods --as=system:serviceaccount:nexus-system:rbaas-operator
```

**Solutions:**
```bash
# 1. Restart operator
kubectl rollout restart deployment/rbaas-operator -n nexus-system

# 2. Check for webhook issues
kubectl get validatingwebhookconfigurations
kubectl get mutatingwebhookconfigurations

# 3. Increase operator verbosity
kubectl set env deployment/rbaas-operator LOG_LEVEL=DEBUG -n nexus-system

# 4. Manually trigger reconciliation
kubectl annotate browsersession <SESSION_NAME> force-sync=true
```

### Issue: KasmVNC session not accessible

**Symptoms:**
```
Cannot connect to browser session URL
Connection refused or timeout
```

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -l app=browser-session

# Check service
kubectl get svc <SESSION_NAME>

# Check ingress
kubectl get ingress <SESSION_NAME>
kubectl describe ingress <SESSION_NAME>

# Test internally
kubectl exec -it <POD_NAME> -- curl localhost:8443
```

**Solutions:**
```bash
# 1. Verify service endpoints
kubectl get endpoints <SESSION_NAME>

# 2. Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# 3. Test with port-forward
kubectl port-forward pod/<POD_NAME> 8443:8443
# Then access https://localhost:8443

# 4. Check NetworkPolicies
kubectl get networkpolicies --all-namespaces
kubectl describe networkpolicy <POLICY_NAME>

# 5. Temporarily disable NetworkPolicy for debugging
kubectl annotate networkpolicy <POLICY_NAME> disabled=true
```

---

## Observability Stack Issues

### Issue: Prometheus not scraping targets

**Symptoms:**
```
Targets showing as "DOWN" in Prometheus UI
No metrics appearing in Grafana
```

**Diagnosis:**
```bash
# Check Prometheus pods
kubectl get pods -n monitoring -l app=prometheus

# Check ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check Prometheus logs
kubectl logs -n monitoring prometheus-prometheus-0 -c prometheus

# Access Prometheus UI
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Visit http://localhost:9090/targets
```

**Solutions:**
```bash
# 1. Verify service labels match ServiceMonitor selector
kubectl get svc <SERVICE_NAME> -o yaml

# 2. Check Prometheus RBAC
kubectl auth can-i list pods --as=system:serviceaccount:monitoring:prometheus-k8s -n <NAMESPACE>

# 3. Recreate ServiceMonitor
kubectl delete servicemonitor <NAME> -n monitoring
kubectl apply -f servicemonitor.yaml

# 4. Reload Prometheus
kubectl exec -n monitoring prometheus-prometheus-0 -- kill -HUP 1
```

### Issue: Grafana dashboards not loading data

**Symptoms:**
```
Grafana shows "No data"
Dashboard variables not populating
```

**Diagnosis:**
```bash
# Check Grafana logs
kubectl logs -n monitoring deployment/grafana -f

# Test Prometheus connectivity from Grafana pod
kubectl exec -n monitoring deployment/grafana -- curl http://prometheus-operated:9090/-/healthy
```

**Solutions:**
```bash
# 1. Verify datasource configuration
# In Grafana UI: Configuration → Data Sources → Prometheus
# URL should be: http://prometheus-operated:9090

# 2. Test PromQL query manually
# In Grafana UI: Explore → Prometheus → Run query

# 3. Re-import dashboard
kubectl create configmap grafana-dashboards \
  --from-file=dashboards/ \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Restart Grafana
kubectl rollout restart deployment/grafana -n monitoring
```

---

## Common Error Messages

### "ERRO[0000] Failed to sandbox network"

**Cause:** CNI plugin misconfiguration

**Solution:**
```bash
# Check CNI plugins
ls /opt/cni/bin/

# Verify K3s CNI config
cat /var/lib/rancher/k3s/agent/etc/cni/net.d/*

# Restart K3s
systemctl restart k3s
```

### "error: unable to recognize: no matches for kind"

**Cause:** CRD not installed or API server not synced

**Solution:**
```bash
# List all CRDs
kubectl get crd

# Wait for API discovery to sync
kubectl api-resources | grep <KIND>

# Re-apply CRD
kubectl apply -f <CRD_FILE>
```

### "OOMKilled"

**Cause:** Container exceeded memory limit

**Solution:**
```bash
# Check pod resource usage
kubectl top pod <POD_NAME>

# Increase memory limits
kubectl set resources deployment/<NAME> --limits=memory=4Gi

# Check node memory pressure
kubectl describe node <NODE> | grep -A5 "Allocated resources"
```

---

## Performance Debugging

### High CPU usage investigation

```bash
# 1. Identify high-CPU pods
kubectl top pods --all-namespaces --sort-by=cpu

# 2. Profile specific pod
kubectl exec -it <POD> -- top

# 3. Get detailed metrics
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/<NS>/pods/<POD>"

# 4. Check for CPU throttling
kubectl get pods -o custom-columns=NAME:.metadata.name,CPU_THROTTLING:.status.containerStatuses[*].state.running.cpuThrottling

# 5. Use crictl for container-level stats
crictl stats <CONTAINER_ID>
```

### Memory leak detection

```bash
# 1. Monitor memory over time
watch kubectl top pods

# 2. Get detailed memory breakdown
kubectl exec <POD> -- cat /proc/meminfo

# 3. Heap profiling (if app supports pprof)
kubectl port-forward <POD> 6060:6060
go tool pprof http://localhost:6060/debug/pprof/heap

# 4. Check for memory pressure events
kubectl get events --all-namespaces | grep -i "memory pressure"
```

---

## Recovery Procedures

### Complete cluster reset

```bash
#!/bin/bash
# DANGER: This destroys everything

# 1. Delete all Kubernetes resources
kubectl delete all --all --all-namespaces

# 2. Uninstall K3s (on all nodes)
/usr/local/bin/k3s-killall.sh
/usr/local/bin/k3s-uninstall.sh  # On server
/usr/local/bin/k3s-agent-uninstall.sh  # On agents

# 3. Clean up
rm -rf /var/lib/rancher/k3s
rm -rf /etc/rancher/k3s

# 4. Destroy VMs (from deployment machine)
cd terraform/
tofu destroy -auto-approve

# 5. Re-run deployment
./deploy.py
```

### Recover from etcd failure

```bash
# On control plane node

# 1. Stop K3s
systemctl stop k3s

# 2. Backup current etcd data
cp -r /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/db.backup

# 3. Restore from snapshot (if available)
k3s server --cluster-reset --cluster-reset-restore-path=/path/to/snapshot

# 4. Start K3s
systemctl start k3s

# 5. Verify cluster health
kubectl get nodes
kubectl get cs
```

### Rollback deployment

```bash
# Kubernetes deployments
kubectl rollout undo deployment/<NAME> -n <NAMESPACE>
kubectl rollout history deployment/<NAME> -n <NAMESPACE>
kubectl rollout undo deployment/<NAME> -n <NAMESPACE> --to-revision=<N>

# Helm releases
helm list -n <NAMESPACE>
helm rollback <RELEASE> <REVISION> -n <NAMESPACE>

# OpenTofu/Terraform
cd terraform/
tofu state pull > backup.tfstate
tofu apply -target=proxmox_virtual_environment_vm.workers
```

---

## Emergency Contacts and Resources

### Useful Commands Reference

```bash
# Quick cluster health check
kubectl get nodes
kubectl get pods --all-namespaces
kubectl cluster-info
kubectl get cs

# Describe everything
kubectl get all --all-namespaces -o wide

# Get events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Check logs for all containers in pod
kubectl logs <POD> --all-containers=true

# Interactive debugging
kubectl debug -it <POD> --image=busybox --target=<CONTAINER>

# Network debugging
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot -- /bin/bash

# Force delete stuck resources
kubectl delete pod <POD> --grace-period=0 --force

# Patch resources
kubectl patch pod <POD> -p '{"metadata":{"finalizers":null}}'
```

### Log Locations

- K3s server: `journalctl -u k3s -f`
- K3s agent: `journalctl -u k3s-agent -f`
- Containerd: `journalctl -u containerd -f`
- Kata runtime: `/var/log/kata-containers/`
- Deployment logs: `./logs/<timestamp>/`

### Port Reference

- API Server: 6443
- Kubelet: 10250
- etcd: 2379-2380
- Prometheus: 9090
- Grafana: 3000
- Jaeger: 16686

---

**Document Version:** 1.0
**Last Updated:** 2025-11-03
**Maintainer:** Nexus DevOps Team
