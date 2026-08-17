# template-config
Scripts to help configure my Proxmox template VMs and the VMs cloned from them.

> These scripts are written for my own network and ship with defaults that reflect it (private
> IPv4 ranges, an internal domain name, and an IPv6 ULA prefix - see below). If you're using these
> scripts outside of my network, look for the comments in `config.sh` and `templatize.sh` marking
> which default values are network-specific and change them (or answer the relevant prompt
> differently) before running.

## Workflow

1. Build/update a "golden" VM (hostname `debian-template`), then run `templatize.sh` on it to scrub
   host-specific state and shut it down. Convert the resulting disk into a Proxmox template.
2. Clone a new VM from the template, boot it, and run `config.sh` to give it its own hostname,
   addressing, and secrets.
3. `regenerate-secrets.sh` is a standalone remediation script for VMs that were already cloned
   from a template before host key regeneration worked correctly (see below) - it rotates a live,
   in-service VM's SSH host keys and systemd random seed without touching anything else.

### Getting these scripts onto a VM

The golden/template VMs are built minimal (no guaranteed network client like `curl`), so these
scripts are never fetched by the guest itself:
- Normally, `proxmox/build-debian-template.sh` (in the `misc` repo) fetches the current versions
  straight into the golden VM's target filesystem using the *build host's* `curl`, before the VM
  ever boots.
- To update an already-built `debian-template` VM without rebuilding it (e.g. after a
  `template-config` change), run `push-scripts.sh [host]` (defaults to `debian-template`) from
  your workstation - it scp's `templatize.sh`/`config.sh` over and fixes ownership/permissions.

## Scripts

- **templatize.sh** - run on the golden VM before converting it to a template. Clears the
  machine-id, SSH host keys, package caches, user history/SSH state, logs, DHCP leases, and the
  systemd random seed, then sets a placeholder network config and shuts the VM down. The
  placeholder config is IPv4-only (`LinkLocalAddressing=ipv4`) since the template has no
  machine-id at this point and accepting the router's RA would trigger a DHCPv6 client that needs
  one to generate a DUID - IPv4 alone is enough to reach the internet for the bootstrap `apt
  update` this network exists for.
- **config.sh** - run as root on a freshly cloned VM. Interactively prompts for hostname, IPv4
  address/prefix/VLAN/gateway, DNS, and the IPv6 ULA prefix (see below), writes the network config
  (IPv4 and IPv6), regenerates the machine-id and SSH host keys, and reboots.
- **push-scripts.sh** - run from your workstation to scp the current `templatize.sh`/`config.sh`
  onto a target VM's `/opt/template-config` (defaults to `debian-template`). See "Getting these
  scripts onto a VM" above - not fetched by `build-debian-template.sh`, never ends up on a
  template or a clone.
- **regenerate-secrets.sh** - run as root on an already-configured, in-service VM to rotate its
  SSH host keys and systemd random seed. Safe to run live: existing SSH sessions are unaffected,
  but any client that has previously connected will see a host key mismatch until it refreshes its
  `known_hosts` (the script prints the new fingerprints and refresh instructions). Not part of the
  golden/clone lifecycle above - a one-off remediation tool, scp it over only when needed.

## IPv6 addressing convention

Every host gets a static IPv6 address in addition to its static IPv4 address, built by encoding
the IPv4 octets and VLAN tag directly into an IPv6 ULA (Unique Local Address, RFC 4193) prefix for
readability:

```
<ULA prefix>:<VLAN tag>:<octet1>:<octet2>:<octet3>:<octet4>
```

For example, with the ULA prefix `fdc1:e344:ba0a` (my own network's prefix, used as the default
below), `10.2.12.100` on VLAN `12` becomes `fdc1:e344:ba0a:12:10:2:12:100`. The gateway uses the same
encoding as the host's own address (same VLAN, IPv4 gateway's octets), since a default gateway
must be on-link with the host's own prefix. DNS servers always use VLAN `1`, regardless of which
VLAN the host itself is on.

**The ULA prefix is private to my network and must not be reused elsewhere** - a ULA prefix is
meant to be randomly generated so that two networks are unlikely to collide if ever connected
(e.g. generate your own at https://www.unique-local-ipv6.com/). `config.sh` prompts for the ULA
prefix (defaulting to mine, for my own convenience - override it if you're not me) along with the
IPv4 address, gateway, and VLAN tag, and computes the IPv6 values automatically. `templatize.sh`'s
placeholder network is IPv4-only (see above), so it has no ULA prefix of its own - it holds its
other settings as variables (`templateIp`, `dnsServer1`, `domain`, etc.) near the top of the file
with a comment marking them as network-specific - edit them there before running.
