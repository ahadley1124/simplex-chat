//
//  UserAddress.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 31/01/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct UserAddress: View {
    @EnvironmentObject private var chatModel: ChatModel
    @State private var alert: UserAddressAlert?
    var viaSettings = false

    private enum UserAddressAlert: Identifiable {
        case deleteAddress
        case error(title: LocalizedStringKey, error: String = "")

        var id: String {
            switch self {
            case .deleteAddress: return "deleteAddress"
            case let .error(title, _): return "error \(title)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack (alignment: .leading) {
                Text("Your contact address")
                    .font(.largeTitle)
                    .bold()
                    .padding(viaSettings ? .bottom : .vertical)
                Text("You can share your address as a link or as a QR code - anybody will be able to connect to you. You won't lose your contacts if you later delete it.")
                    .padding(.bottom)
                if let userAdress = chatModel.userAddress {
                    QRCode(uri: userAdress)
                    HStack {
                        Button {
                            showShareSheet(items: [userAdress])
                        } label: {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                        .padding()

                        Button(role: .destructive) { alert = .deleteAddress } label: {
                            Label("Delete address", systemImage: "trash")
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        Task {
                            do {
                                let userAddress = try await apiCreateUserAddress()
                                DispatchQueue.main.async {
                                    chatModel.userAddress = userAddress
                                }
                            } catch let error {
                                logger.error("UserAddress apiCreateUserAddress: \(error.localizedDescription)")
                                switch error as? ChatResponse {
                                case .chatCmdError(.errorAgent(.BROKER(.TIMEOUT))):
                                    alert = .error(title: "Connection timeout", error: "Please check your network connection and try again.")
                                case .chatCmdError(.errorAgent(.BROKER(.NETWORK))):
                                    alert = .error(title: "Connection error", error: "Please check your network connection and try again.")
                                default:
                                    alert = .error(title: "Error creating address", error: "Error: \(responseError(error))")
                                }
                            }
                        }
                    } label: { Label("Create address", systemImage: "qrcode") }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .alert(item: $alert) { alert in
                switch alert {
                case .deleteAddress:
                    return Alert(
                        title: Text("Delete address?"),
                        message: Text("All your contacts will remain connected"),
                        primaryButton: .destructive(Text("Delete")) {
                            Task {
                                do {
                                    try await apiDeleteUserAddress()
                                    DispatchQueue.main.async {
                                        chatModel.userAddress = nil
                                    }
                                } catch let error {
                                    logger.error("UserAddress apiDeleteUserAddress: \(error.localizedDescription)")
                                }
                            }
                        }, secondaryButton: .cancel()
                    )
                case let .error(title, error):
                    return Alert(title: Text(title), message: Text("\(error)"))
                }
            }
        }
    }
}

struct UserAddress_Previews: PreviewProvider {
    static var previews: some View {
        let chatModel = ChatModel()
        chatModel.userAddress = "https://simplex.chat/contact#/?v=1&smp=smp%3A%2F%2FPQUV2eL0t7OStZOoAsPEV2QYWt4-xilbakvGUGOItUo%3D%40smp6.simplex.im%2FK1rslx-m5bpXVIdMZg9NLUZ_8JBm8xTt%23MCowBQYDK2VuAyEALDeVe-sG8mRY22LsXlPgiwTNs9dbiLrNuA7f3ZMAJ2w%3D"
        return Group {
            UserAddress()
                .environmentObject(chatModel)
            UserAddress()
                .environmentObject(ChatModel())
        }
    }
}
