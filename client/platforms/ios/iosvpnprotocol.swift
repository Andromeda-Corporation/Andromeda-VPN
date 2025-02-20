/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import NetworkExtension

let vpnName = "Amnezia WireguardVPN"
var vpnBundleID = "";

@objc class VPNIPAddressRange : NSObject {
    public var address: NSString = ""
    public var networkPrefixLength: UInt8 = 0
    public var isIpv6: Bool = false

    @objc init(address: NSString, networkPrefixLength: UInt8, isIpv6: Bool) {
        super.init()

        self.address = address
        self.networkPrefixLength = networkPrefixLength
        self.isIpv6 = isIpv6
    }
}

public class IOSVpnProtocolImpl : NSObject {

    private var tunnel: NETunnelProviderManager? = nil
    private var stateChangeCallback: ((Bool) -> Void?)? = nil
    private var privateKey : PrivateKey? = nil
    private var deviceIpv4Address: String? = nil
    private var deviceIpv6Address: String? = nil

    @objc enum ConnectionState: Int { case Error, Connected, Disconnected }
    
    @objc init(bundleID: String,
               config: String,
               closure: @escaping (ConnectionState, Date?) -> Void,
               callback: @escaping (Bool) -> Void) {
        super.init()
        Logger.configureGlobal(tagged: "APP", withFilePath: "")
        
        print("Config from caller: \(config)")

        vpnBundleID = bundleID;
        precondition(!vpnBundleID.isEmpty)
        
        stateChangeCallback = callback
        
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.vpnStatusDidChange(notification:)),
                                               name: Notification.Name.NEVPNStatusDidChange,
                                               object: nil)

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                Logger.global?.log(message: "Loading from preference failed: \(error)")
                closure(ConnectionState.Error, nil)
                return
            }

            if self == nil {
                Logger.global?.log(message: "We are shutting down.")
                return
            }

            let nsManagers = managers ?? []
            Logger.global?.log(message: "We have received \(nsManagers.count) managers.")
            print("We have received \(nsManagers.count) managers.")

            let tunnel = nsManagers.first(where: IOSVpnProtocolImpl.isOurManager(_:))
            
//            if let name = tunnel?.localizedDescription, name == vpnName {
//                tunnel?.removeFromPreferences(completionHandler: { removeError in
//                    if let error = removeError {
//                        Logger.global?.log(message: "WireguardVPN Tunnel Remove from Prefs Error: \(error)")
//                        closure(ConnectionState.Error, nil)
//                        return
//                    }
//                })
//            }
            
            if tunnel == nil {
                Logger.global?.log(message: "Creating the tunnel")
                print("Creating the tunnel")
                self!.tunnel = NETunnelProviderManager()
                closure(ConnectionState.Disconnected, nil)
                return
            }

            Logger.global?.log(message: "Tunnel already exists")
            print("Tunnel already exists")

            self!.tunnel = tunnel
            if tunnel?.connection.status == .connected {
                closure(ConnectionState.Connected, tunnel?.connection.connectedDate)
            } else {
                closure(ConnectionState.Disconnected, nil)
            }
        }
    }

    @objc init(bundleID: String,
               privateKey: Data,
               deviceIpv4Address: String,
               deviceIpv6Address: String,
               closure: @escaping (ConnectionState, Date?) -> Void,
               callback: @escaping (Bool) -> Void) {
        super.init()

        Logger.configureGlobal(tagged: "APP", withFilePath: "")

        vpnBundleID = bundleID;
        precondition(!vpnBundleID.isEmpty)
        
        stateChangeCallback = callback
        self.privateKey = PrivateKey(rawValue: privateKey)
        self.deviceIpv4Address = deviceIpv4Address
        self.deviceIpv6Address = deviceIpv6Address
        
        NotificationCenter.default.removeObserver(self)

        NotificationCenter.default.addObserver(self, selector: #selector(self.vpnStatusDidChange(notification:)), name: Notification.Name.NEVPNStatusDidChange, object: nil)

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                Logger.global?.log(message: "Loading from preference failed: \(error)")
                closure(ConnectionState.Error, nil)
                return
            }

            if self == nil {
                Logger.global?.log(message: "We are shutting down.")
                return
            }

            let nsManagers = managers ?? []
            Logger.global?.log(message: "We have received \(nsManagers.count) managers.")
            print("We have received \(nsManagers.count) managers.")

            let tunnel = nsManagers.first(where: IOSVpnProtocolImpl.isOurManager(_:))
            
//            if let name = tunnel?.localizedDescription, name != vpnName {
//                tunnel?.removeFromPreferences(completionHandler: { removeError in
//                    if let error = removeError {
//                        Logger.global?.log(message: "OpenVpn Tunnel Remove from Prefs Error: \(error)")
//                        closure(ConnectionState.Error, nil)
//                        return
//                    }
//                })
//            }
            
            if tunnel == nil {
                Logger.global?.log(message: "Creating the tunnel")
                print("Creating the tunnel")
                self!.tunnel = NETunnelProviderManager()
                closure(ConnectionState.Disconnected, nil)
                return
            }
            
            Logger.global?.log(message: "Tunnel already exists")
            print("Tunnel already exists")

            self!.tunnel = tunnel
            
            if tunnel?.connection.status == .connected {
                closure(ConnectionState.Connected, tunnel?.connection.connectedDate)
            } else {
                closure(ConnectionState.Disconnected, nil)
            }
        }
    }

    @objc private func vpnStatusDidChange(notification: Notification) {
        guard let session = (notification.object as? NETunnelProviderSession), tunnel?.connection == session else { return }

        switch session.status {
        case .connected:
            Logger.global?.log(message: "STATE CHANGED: connected")
            print("STATE CHANGED: connected")
        case .connecting:
            Logger.global?.log(message: "STATE CHANGED: connecting")
            print("STATE CHANGED: connecting")
        case .disconnected:
            Logger.global?.log(message: "STATE CHANGED: disconnected")
            print("STATE CHANGED: disconnected")
        case .disconnecting:
            Logger.global?.log(message: "STATE CHANGED: disconnecting")
            print("STATE CHANGED: disconnecting")
        case .invalid:
            Logger.global?.log(message: "STATE CHANGED: invalid")
            print("STATE CHANGED: invalid")
        case .reasserting:
            Logger.global?.log(message: "STATE CHANGED: reasserting")
            print("STATE CHANGED: reasserting")
        default:
            Logger.global?.log(message: "STATE CHANGED: unknown status")
            print("STATE CHANGED: unknown status")
        }

        // We care about "unknown" state changes.
        if (session.status != .connected && session.status != .disconnected) {
            return
        }

        stateChangeCallback?(session.status == .connected)
    }

    private static func isOurManager(_ manager: NETunnelProviderManager) -> Bool {
        guard
            let proto = manager.protocolConfiguration,
            let tunnelProto = proto as? NETunnelProviderProtocol
        else {
            Logger.global?.log(message: "Ignoring manager because the proto is invalid.")
            return false
        }

        if (tunnelProto.providerBundleIdentifier == nil) {
            Logger.global?.log(message: "Ignoring manager because the bundle identifier is null.")
            return false
        }

        if (tunnelProto.providerBundleIdentifier != vpnBundleID) {
            Logger.global?.log(message: "Ignoring manager because the bundle identifier doesn't match.")
            return false;
        }

        Logger.global?.log(message: "Found the manager with the correct bundle identifier: \(tunnelProto.providerBundleIdentifier!)")
        print("Found the manager with the correct bundle identifier: \(tunnelProto.providerBundleIdentifier!)")
        return true
    }
    
    @objc func connect(ovpnConfig: String, failureCallback: @escaping () -> Void) {
        Logger.global?.log(message: "Connecting")
        assert(tunnel != nil)
        
        let addr: String = ovpnConfig
            .splitToArray(separator: "\n", trimmingCharacters: nil)
            .first {  $0.starts(with: "remote ") }
            .splitToArray(separator: " ", trimmingCharacters: nil)[1]
        print("server: \(addr)")
        
        // Let's remove the previous config if it exists.
        (tunnel?.protocolConfiguration as? NETunnelProviderProtocol)?.destroyConfigurationReference()
        
        self.configureOpenVPNTunnel(serverAddress: addr, config: ovpnConfig, failureCallback: failureCallback)
    }

    @objc func connect(dnsServer: String, serverIpv6Gateway: String, serverPublicKey: String, presharedKey: String, serverIpv4AddrIn: String, serverPort: Int,  allowedIPAddressRanges: Array<VPNIPAddressRange>, ipv6Enabled: Bool, reason: Int, failureCallback: @escaping () -> Void) {
        Logger.global?.log(message: "Connecting")
        assert(tunnel != nil)

        // Let's remove the previous config if it exists.
        (tunnel?.protocolConfiguration as? NETunnelProviderProtocol)?.destroyConfigurationReference()

        let keyData = PublicKey(base64Key: serverPublicKey)!
        let dnsServerIP = IPv4Address(dnsServer)
        let ipv6GatewayIP = IPv6Address(serverIpv6Gateway)

        var peerConfiguration = PeerConfiguration(publicKey: keyData)
        peerConfiguration.preSharedKey = PreSharedKey(base64Key: presharedKey)
        peerConfiguration.endpoint = Endpoint(from: serverIpv4AddrIn + ":\(serverPort )")
        peerConfiguration.allowedIPs = []

        allowedIPAddressRanges.forEach {
            if (!$0.isIpv6) {
                peerConfiguration.allowedIPs.append(IPAddressRange(address: IPv4Address($0.address as String)!, networkPrefixLength: $0.networkPrefixLength))
            } else if (ipv6Enabled) {
                peerConfiguration.allowedIPs.append(IPAddressRange(address: IPv6Address($0.address as String)!, networkPrefixLength: $0.networkPrefixLength))
            }
        }

        var peerConfigurations: [PeerConfiguration] = []
        peerConfigurations.append(peerConfiguration)

        var interface = InterfaceConfiguration(privateKey: privateKey!)

        if let ipv4Address = IPAddressRange(from: deviceIpv4Address!),
           let ipv6Address = IPAddressRange(from: deviceIpv6Address!) {
            interface.addresses = [ipv4Address]
            if (ipv6Enabled) {
                interface.addresses.append(ipv6Address)
            }
        }
        interface.dns = [ DNSServer(address: dnsServerIP!)]
        interface.mtu = 1412 // 1280

        if (ipv6Enabled) {
            interface.dns.append(DNSServer(address: ipv6GatewayIP!))
        }

        let config = TunnelConfiguration(name: vpnName, interface: interface, peers: peerConfigurations)

        self.configureTunnel(config: config, reason: reason, failureCallback: failureCallback)
    }

    func configureTunnel(config: TunnelConfiguration, reason: Int, failureCallback: @escaping () -> Void) {
        guard let proto = NETunnelProviderProtocol(tunnelConfiguration: config) else {
            failureCallback()
            return
        }
        proto.providerBundleIdentifier = vpnBundleID

        tunnel!.protocolConfiguration = proto
        tunnel!.localizedDescription = vpnName
        tunnel!.isEnabled = true

        tunnel!.saveToPreferences { [unowned self] saveError in
            if let error = saveError {
                Logger.global?.log(message: "Connect Tunnel Save Error: \(error)")
                failureCallback()
                return
            }

            Logger.global?.log(message: "Saving the tunnel succeeded")

            self.tunnel!.loadFromPreferences { error in
                if let error = error {
                    Logger.global?.log(message: "Connect Tunnel Load Error: \(error)")
                    failureCallback()
                    return
                }

                Logger.global?.log(message: "Loading the tunnel succeeded")
                print("Loading the tunnel succeeded")

                do {
                    if (reason == 1 /* ReasonSwitching */) {
                        let settings = config.asWgQuickConfig()
                        let settingsData = settings.data(using: .utf8)!
                        try (self.tunnel!.connection as? NETunnelProviderSession)?
                                .sendProviderMessage(settingsData) { data in
                            guard let data = data,
                                let configString = String(data: data, encoding: .utf8)
                            else {
                                Logger.global?.log(message: "Failed to convert response to string")
                                return
                            }
                            print("Config sent to NE: \(configString)")
                        }
                    } else {
                        print("starting tunnel")
                        try (self.tunnel!.connection as? NETunnelProviderSession)?.startTunnel()
                    }
                } catch let error {
                    Logger.global?.log(message: "Something went wrong: \(error)")
                    failureCallback()
                    return
                }
            }
        }
    }
    
    func configureOpenVPNTunnel(serverAddress: String, config: String, failureCallback: @escaping () -> Void) {
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.serverAddress = serverAddress
        tunnelProtocol.providerBundleIdentifier = vpnBundleID
        tunnelProtocol.providerConfiguration = ["ovpn": Data(config.utf8)]
        tunnel?.protocolConfiguration = tunnelProtocol
        tunnel?.localizedDescription = "Amnezia OpenVPN"
        tunnel?.isEnabled = true

        tunnel?.saveToPreferences { [unowned self] saveError in
            if let error = saveError {
                Logger.global?.log(message: "Connect OpenVPN Tunnel Save Error: \(error)")
                failureCallback()
                return
            }

            Logger.global?.log(message: "Saving the OpenVPN tunnel succeeded")

            self.tunnel?.loadFromPreferences { error in
                if let error = error {
                    Logger.global?.log(message: "Connect OpenVPN Tunnel Load Error: \(error)")
                    failureCallback()
                    return
                }

                Logger.global?.log(message: "Loading the OpenVPN tunnel succeeded")
                print("Loading the openvpn tunnel succeeded")

                do {
                    print("starting openvpn tunnel")
                    try self.tunnel?.connection.startVPNTunnel()
                } catch let error {
                    Logger.global?.log(message: "Something went wrong: \(error)")
                    failureCallback()
                    return
                }
            }
        }
    }

    @objc func disconnect() {
        Logger.global?.log(message: "Disconnecting")
        assert(tunnel != nil)
        (tunnel!.connection as? NETunnelProviderSession)?.stopTunnel()
    }

    @objc func checkStatus(callback: @escaping (String, String, String) -> Void) {
        Logger.global?.log(message: "Check status")
        assert(tunnel != nil)
        
        let protoType = (tunnel!.localizedDescription ?? "").toTunnelType
        
        switch protoType {
        case .wireguard:
            checkWireguardStatus(callback: callback)
        case .openvpn:
            checkOVPNStatus(callback: callback)
        case .empty:
            break
        }
        
    }
    
    private func checkOVPNStatus(callback: @escaping (String, String, String) -> Void) {
        Logger.global?.log(message: "Check OpenVPN")
        guard let proto = tunnel?.protocolConfiguration as? NETunnelProviderProtocol else {
            callback("", "", "")
            return
        }
        
        guard let configData = proto.providerConfiguration?["ovpn"] as? Data,
              let ovpnConfig = String(data: configData, encoding: .utf8) else  {
            callback("", "", "")
            return
        }
        
        let serverIpv4Gateway: String = ovpnConfig
            .splitToArray(separator: "\n", trimmingCharacters: nil)
            .first {  $0.starts(with: "remote ") }
            .splitToArray(separator: " ", trimmingCharacters: nil)[1]
        
        print("server IP: \(serverIpv4Gateway)")
        
        
        let deviceIpv4Address = getTunIPAddress()
        print("device IP: \(serverIpv4Gateway)")
        if deviceIpv4Address == nil {
            callback("", "", "")
            return
        }
        
        guard let session = tunnel?.connection as? NETunnelProviderSession else {
            callback("", "", "")
            return
        }
        
        do {
            try session.sendProviderMessage(Data([UInt8(0)])) { [callback] data in
                guard let data = data,
                      let configString = String(data: data, encoding: .utf8)
                else {
                    Logger.global?.log(message: "Failed to convert data to string")
                    callback("", "", "")
                    return
                }

                callback("\(serverIpv4Gateway)", "\(deviceIpv4Address!)", configString)
            }
        } catch {
            Logger.global?.log(message: "Failed to retrieve data from session")
            callback("", "", "")
        }
        
    }
    
    private func checkWireguardStatus(callback: @escaping (String, String, String) -> Void) {
        Logger.global?.log(message: "Check Wireguard")
        let proto = tunnel!.protocolConfiguration as? NETunnelProviderProtocol
        if proto == nil {
            callback("", "", "")
            return
        }

        let tunnelConfiguration = proto?.asTunnelConfiguration()
        if tunnelConfiguration == nil {
            callback("", "", "")
            return
        }

        let serverIpv4Gateway = tunnelConfiguration?.interface.dns[0].address
        if serverIpv4Gateway == nil {
            callback("", "", "")
            return
        }

        let deviceIpv4Address = tunnelConfiguration?.interface.addresses[0].address
        if deviceIpv4Address == nil {
            callback("", "", "")
            return
        }

        guard let session = tunnel?.connection as? NETunnelProviderSession
        else {
            callback("", "", "")
            return
        }

        do {
            try session.sendProviderMessage(Data([UInt8(0)])) { [callback] data in
                guard let data = data,
                      let configString = String(data: data, encoding: .utf8)
                else {
                    Logger.global?.log(message: "Failed to convert data to string")
                    callback("", "", "")
                    return
                }

                callback("\(serverIpv4Gateway!)", "\(deviceIpv4Address!)", configString)
            }
        } catch {
            Logger.global?.log(message: "Failed to retrieve data from session")
            callback("", "", "")
        }
    }
    
    private func getTunIPAddress() -> String? {
        var address: String? = nil
        var interfaces: UnsafeMutablePointer<ifaddrs>? = nil
        var temp_addr: UnsafeMutablePointer<ifaddrs>? = nil
        var success: Int = 0
       
        // retrieve the current interfaces - returns 0 on success
        success = Int(getifaddrs(&interfaces))
        if success == 0 {
            // Loop through linked list of interfaces
            temp_addr = interfaces
            while temp_addr != nil {
                if temp_addr?.pointee.ifa_addr == nil {
                     continue
                }
                if temp_addr?.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                    // Check if interface is en0 which is the wifi connection on the iPhone
                    if let name = temp_addr?.pointee.ifa_name, ((String(utf8String: name)?.contains("tun")) != nil) {
                        // Get NSString from C String
                        if let value = temp_addr?.pointee.ifa_addr as? sockaddr_in {
                            address = String(utf8String: inet_ntoa(value.sin_addr))
                        }
                    }
                }
                temp_addr = temp_addr?.pointee.ifa_next
            }
        }
        freeifaddrs(interfaces)
        return address
    }
}

enum TunnelType: String {
    case wireguard, openvpn, empty
}

extension String {
    var toTunnelType: TunnelType {
        switch self {
        case "wireguard": return .wireguard
        case "openvpn": return .openvpn
        default:
            return .empty
        }
    }
}
