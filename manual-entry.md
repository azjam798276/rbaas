# Manual Entry Instructions for Proxmox Host

This document consolidates all manual steps performed on the Proxmox host (`10.1.0.101`) to set up the environment for the Nexus Sandbox Framework deployment.

---

## 1. Enable Public Key Authentication for SSH

To allow passwordless SSH login, you need to ensure your Proxmox host accepts public key authentication. You should have already copied your SSH public key to the Proxmox host.

1.  **SSH into your Proxmox host:**

    ```bash
    ssh rocm@10.1.0.101
    ```

2.  **Open the SSH configuration file** using a text editor like `nano`:

    ```bash
    sudo nano /etc/ssh/sshd_config
    ```

3.  **Ensure `PubkeyAuthentication` is set to `yes`** and is not commented out (the line should not start with a `#`). It should look like this:

    ```
    PubkeyAuthentication yes
    ```

4.  **Save the file and exit `nano`** by pressing `Ctrl+X`, then `Y`, and then `Enter`.

5.  **Restart the SSH service** for the changes to take effect:

    ```bash
    sudo systemctl restart sshd
    ```

---

## 2. Create `ansible_user` on Proxmox

We need a dedicated user for Ansible automation. This user will be created as a Linux user and then registered with Proxmox's user management system.

1.  **Log in to your Proxmox host as `rocm`** (or another user with `sudo` privileges).

2.  **Create the `ansible_user` Linux user and add them to the `sudo` group:**

    ```bash
    sudo useradd -m -s /bin/bash ansible_user
    sudo adduser ansible_user sudo
    ```

---

## 3. Create Proxmox API Token for `ansible_user`

An API token is required for programmatic access to the Proxmox API. This token will be associated with the `ansible_user`.

1.  **Log in to your Proxmox host as `root`** (or a user with sufficient privileges to manage Proxmox users and tokens).

2.  **Register `ansible_user` with Proxmox's PAM realm:**

    ```bash
    /usr/sbin/pveum user add ansible_user@pam
    ```
    You will be prompted to set a password for this user.

3.  **Create the API token for `ansible_user`:**

    ```bash
    /usr/sbin/pveum user token add ansible_user@pam ansible_token --privsep 0 --expire 0 --comment 'Token for Ansible automation'
    ```
    **Record the `PM_API_TOKEN_ID` and `PM_API_TOKEN_SECRET` from the output of this command.** You will need these values later.

---

## 4. Manage GPU Drivers (Blacklisting `nouveau`, Enabling `vfio`)

To enable GPU passthrough, you need to disable the `nouveau` driver and enable `vfio` modules on your Proxmox host. A script was created to automate this.

1.  **Copy the `manage_gpu_drivers.sh` script to your Proxmox host.** (e.g., to the `rocm` user's home directory):

    ```bash
    scp /home/rocm/rbaas/manage_gpu_drivers.sh rocm@10.1.0.101:~/manage_gpu_drivers.sh
    ```

2.  **SSH into your Proxmox host:**

    ```bash
    ssh rocm@10.1.0.101
    ```

3.  **Make the script executable:**

    ```bash
    chmod +x ~/manage_gpu_drivers.sh
    ```

4.  **Run the script to enable `vfio`:**

    ```bash
    sudo ~/manage_gpu_drivers.sh on
    ```

5.  **Reboot your Proxmox host** for the changes to take effect:

    ```bash
    sudo reboot
    ```

---

## 5. Create `AnsibleRole` and Assign to `ansible_user`

The `ansible_user` needs specific permissions to interact with Proxmox resources. We will create a custom role and assign it to the user.

1.  **Log in to your Proxmox host as `root`** (or a user with sufficient privileges to manage Proxmox roles and ACLs).

2.  **Create the `AnsibleRole`:**

    ```bash
    /usr/sbin/pveum role add AnsibleRole -privs "Sys.Audit VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.PowerMgmt Datastore.Audit Datastore.Allocate"
    ```

3.  **Assign the `AnsibleRole` to `ansible_user` at the root path (`/`):**

    ```bash
    /usr/sbin/pveum acl modify / -user ansible_user@pam -role AnsibleRole
    ```

---

## 6. Create Cloud-Init Template

This template will be used as the base for all virtual machines provisioned by the deployment. Ensure the `jammy-server-cloudimg-amd64.img` is in the `/root` directory on your Proxmox host.

1.  **Log in to your Proxmox host as `root`** (or a user with `sudo` privileges).

2.  **Destroy any existing VM with ID 9000** (if you attempted to create it before):

    ```bash
    qm destroy 9000
    ```

3.  **Create the base VM for the template:**

    ```bash
    qm create 9000 --name ubuntu-2204-cloudinit-template --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
    ```

4.  **Import the downloaded cloud image to your `LVM` storage pool:**

    ```bash
    qm importdisk 9000 /root/jammy-server-cloudimg-amd64.img LVM
    ```

5.  **Attach the imported disk to the VM and configure SCSI hardware:**

    ```bash
    qm set 9000 --scsihw virtio-scsi-pci --scsi0 LVM:vm-9000-disk-0
    ```

6.  **Configure the cloud-init drive on the `local` storage pool and set the boot order:**

    ```bash
    qm set 9000 --ide2 local:cloudinit --boot c --bootdisk scsi0
    ```

7.  **Finalize the template settings (serial console, VGA, QEMU guest agent):**

    ```bash
    qm set 9000 --serial0 socket --vga serial0 --agent enabled=1
    ```

8.  **Convert the VM to a template:**

    ```bash
    qm template 9000
    ```
