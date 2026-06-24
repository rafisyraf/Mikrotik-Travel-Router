# ==============================================================================
# MikroTik RouterOS V7 Config
# ==============================================================================
# For MikroTik hAP lite (SMIPS) / Clean Slate (No Default Configuration)
# Topology: ether1 (WAN Ingress from Modem) | ether2-4 + wlan1 (Local Bridge)

# ------------------------------------------------------------------------------
# Local Bridge Configuration
# ------------------------------------------------------------------------------
# Create a unified Layer 2 bridge domain for all local trusted assets
/interface bridge add name=bridge-local comment="Unified LAN/WLAN Bridge Switch"

# Bind physical interfaces ether2, ether3, and ether4 to the trusted switch
/interface bridge port
add bridge=bridge-local interface=ether2
add bridge=bridge-local interface=ether3
add bridge=bridge-local interface=ether4

# ------------------------------------------------------------------------------
# 2. Wifi Hotspot/Broadcast Wifi
# ------------------------------------------------------------------------------
# Define cryptographic parameters for local Wi-Fi connection
/interface wireless security-profiles
add name=travel-vault-profile \
    mode=dynamic-keys \
    authentication-types=wpa2-psk \
    wpa2-pre-shared-key="YOUR_ROUTER_WIFI_PASSWORD"

# Configure the 2.4GHz internal radio to broadcast the secure SSID
/interface wireless
set [ find default-name=wlan1 ] \
    mode=ap-bridge \
    ssid="YOUR_SECURE_TRAVEL_SSID" \
    security-profile=travel-vault-profile \
    band=2ghz-b/g/n \
    frequency=auto \
    installation=indoor \
    disabled=no

# Bind the radio asset to our trusted local switch domain
/interface bridge port add bridge=bridge-local interface=wlan1

# ------------------------------------------------------------------------------
# 3. Lan IP & DHCP Server
# ------------------------------------------------------------------------------
# Assign local gateway residency to the bridge interface
/ip address add address=192.168.88.1/24 interface=bridge-local

# Construct the local client IP address pool
/ip pool add name=dhcp-pool-local ranges=192.168.88.10-192.168.88.254

# Instantiate and bind the DHCP network server engine
/ip dhcp-server add name=dhcp-lan-server interface=bridge-local address-pool=dhcp-pool-local disabled=no

# Configure distributed DHCP leases to point DNS inside the VPN tunnel endpoint 
# to structurally eliminate DNS leaks at the local node level.
/ip dhcp-server network add address=192.168.88.0/24 gateway=192.168.88.1 dns-server=10.2.0.1 comment="Enforce Inner-Tunnel DNS Engine"

# ------------------------------------------------------------------------------
# 4. WAN Configuration via Modem Connection
# ------------------------------------------------------------------------------
# Listen on ether1 for incoming DHCP configuration vectors served by the Orbit
/ip dhcp-client add interface=ether1 use-peer-dns=yes use-peer-ntp=yes disabled=no comment="Ingress from Telkomsel Orbit"

# ------------------------------------------------------------------------------
# 5. WireGuard VPN Setup
# ------------------------------------------------------------------------------
# Initialize the stateful native WireGuard interface
/interface wireguard add listen-port=51820 name=wg-proton private-key="YOUR_VPN_PRIVATE_KEY"

# Allocate the explicit inside-tunnel address given by the provider
/ip address add address=10.2.0.2/24 interface=wg-proton network=10.2.0.0

# Register the cryptographic endpoint signature of the upstream exit node
/interface wireguard peers
add interface=wg-proton \
    public-key="SERVER_VPN_PUBLIC_KEY" \
    endpoint-address=SG_SERVER_IP_OR_HOSTNAME \
    endpoint-port=51820 \
    allowed-address=0.0.0.0/0 \
    persistent-keepalive=25s \
    comment="Primary Cryptographic Gateway Node"

# ------------------------------------------------------------------------------
# 6. Policy Routing & Tunnel Enforcement (RouterOS v7 Format)
# ------------------------------------------------------------------------------
# Provision a dedicated routing data table structure inside the kernel
/routing table add name=tunnel-delivery-table fib

# Bind a complete universal destination path out through the WireGuard pipe inside that specific table
/ip route add dst-address=0.0.0.0/0 gateway=wg-proton routing-table=tunnel-delivery-table

# Build a structural hard Kill Switch: if the tunnel breaks down, drop packets 
# into a blackhole instead of passing them unsecured through the local ISP/Orbit gateway.
/ip route add dst-address=0.0.0.0/0 type=blackhole routing-table=tunnel-delivery-table distance=10

# Direct all traffic entering from our local address matrix to evaluate using the VPN table
/routing rule add src-address=192.168.88.0/24 action=lookup table=tunnel-delivery-table

# ------------------------------------------------------------------------------
# 7. NAT & MSS Clamping
# ------------------------------------------------------------------------------
# Hide local address scope behind inside-tunnel IP representation
/ip firewall nat add chain=srcnat out-interface=wg-proton action=masquerade comment="Masquerade VPN Traffic"

# Keep an alternative fallback masquerade rule for local management data escaping on WAN interface
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade comment="Masquerade WAN Failover"

# Clamp MSS over VPN to account for cryptographic payload headers over standard ISP 1500-byte frame structures
/ip firewall mangle
add chain=forward action=change-mss new-mss=clamp-to-pmtu passthrough=yes protocol=tcp tcp-flags=syn out-interface=wg-proton comment="Prevent MTU Fragment Collisions"
