//
//  NetworkServersView.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 02/08/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

enum OnionHostsAlert: Identifiable {
    case update(hosts: OnionHosts)
    case error(err: String)

    var id: String {
        switch self {
        case let .update(hosts): return "update \(hosts)"
        case let .error(err): return "error \(err)"
        }
    }
}

struct NetworkAndServers: View {
    @AppStorage(DEFAULT_DEVELOPER_TOOLS) private var developerTools = false
    @State private var cfgLoaded = false
    @State private var currentNetCfg = NetCfg.defaults
    @State private var netCfg = NetCfg.defaults
    @State private var onionHosts: OnionHosts = .no
    @State private var showOnionHostsAlert: OnionHostsAlert?

    var body: some View {
        VStack {
            List {
                Section {
                    NavigationLink {
                        SMPServers()
                            .navigationTitle("Your SMP servers")
                    } label: {
                        Text("SMP servers")
                    }

                    Picker("Use .onion hosts", selection: $onionHosts) {
                        ForEach(OnionHosts.values, id: \.self) { Text($0.text) }
                    }

                    if developerTools {
                        NavigationLink {
                            AdvancedNetworkSettings()
                                .navigationTitle("Network settings")
                        } label: {
                            Text("Advanced network settings")
                        }
                    }
                } header: {
                    Text("Messages")
                } footer: {
                    Text("Using .onion hosts requires compatible VPN provider.")
                }

                Section("Calls") {
                    NavigationLink {
                        RTCServers()
                            .navigationTitle("Your ICE servers")
                    } label: {
                        Text("WebRTC ICE servers")
                    }
                }
            }
        }
        .onAppear {
            if cfgLoaded { return }
            cfgLoaded = true
            currentNetCfg = getNetCfg()
            resetNetCfgView()
        }
        .onChange(of: onionHosts) { _ in
            if onionHosts != OnionHosts(netCfg: currentNetCfg) {
                showOnionHostsAlert = .update(hosts: onionHosts)
            }
        }
        .alert(item: $showOnionHostsAlert) { a in
            switch a {
            case let .update(hosts):
                return Alert(
                    title: Text("Update .onion hosts setting?"),
                    message: Text(onionHostsInfo()) + Text("\n") + Text("Updating this setting will re-connect the client to all servers."),
                    primaryButton: .default(Text("Ok")) {
                        saveNetCfg(hosts)
                    },
                    secondaryButton: .cancel() {
                        resetNetCfgView()
                    }
                )
            case let .error(err):
                return Alert(
                    title: Text("Error updating settings"),
                    message: Text(err)
                )
            }
        }
    }

    private func saveNetCfg(_ hosts: OnionHosts) {
        do {
            let (hostMode, requiredHostMode) = hosts.hostMode
            netCfg.hostMode = hostMode
            netCfg.requiredHostMode = requiredHostMode
            let def = netCfg.hostMode == .onionHost ? NetCfg.proxyDefaults : NetCfg.defaults
            netCfg.tcpConnectTimeout = def.tcpConnectTimeout
            netCfg.tcpTimeout = def.tcpTimeout
            try setNetworkConfig(netCfg)
            currentNetCfg = netCfg
            setNetCfg(netCfg)
        } catch let error {
            let err = responseError(error)
            resetNetCfgView()
            showOnionHostsAlert = .error(err: err)
            logger.error("\(err)")
        }
    }

    private func resetNetCfgView() {
        netCfg = currentNetCfg
        onionHosts = OnionHosts(netCfg: netCfg)
    }

    private func onionHostsInfo() -> LocalizedStringKey {
        switch onionHosts {
        case .no: return "Onion hosts will not be used."
        case .prefer: return "Onion hosts will be used when available. Requires enabling VPN."
        case .require: return "Onion hosts will be required for connection. Requires enabling VPN."
        }
    }
}

struct NetworkServersView_Previews: PreviewProvider {
    static var previews: some View {
        NetworkAndServers()
    }
}
