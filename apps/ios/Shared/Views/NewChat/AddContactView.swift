//
//  AddContactView.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 29/01/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import SimpleXChat

struct AddContactView: View {
    @EnvironmentObject private var chatModel: ChatModel
    var contactConnection: PendingContactConnection? = nil
    var connReqInvitation: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Your contact can scan it from the app.")
                    .padding(.bottom, 4)
                if (contactConnection?.incognito ?? chatModel.incognito) {
                    HStack {
                        Image(systemName: "theatermasks").foregroundColor(.indigo).font(.footnote)
                        Spacer().frame(width: 8)
                        Text("A random profile will be sent to your contact").font(.footnote)
                    }
                    .padding(.bottom)
                } else {
                    HStack {
                        Image(systemName: "info.circle").foregroundColor(.secondary).font(.footnote)
                        Spacer().frame(width: 8)
                        Text("Your chat profile will be sent to your contact").font(.footnote)
                    }
                    .padding(.bottom)
                }
                if connReqInvitation != "" {
                    QRCode(uri: connReqInvitation).padding(.bottom)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical)
                }
                Text("If you can't meet in person, **show QR code in the video call**, or share the link.")
                    .padding(.bottom)
                Button {
                    showShareSheet(items: [connReqInvitation])
                } label: {
                    Label("Share invitation link", systemImage: "square.and.arrow.up")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { chatModel.connReqInv = connReqInvitation }
    }
}

struct AddContactView_Previews: PreviewProvider {
    static var previews: some View {
        AddContactView(connReqInvitation: "https://simplex.chat/invitation#/?v=1&smp=smp%3A%2F%2Fu2dS9sG8nMNURyZwqASV4yROM28Er0luVTx5X1CsMrU%3D%40smp4.simplex.im%2FFe5ICmvrm4wkrr6X1LTMii-lhBqLeB76%23MCowBQYDK2VuAyEAdhZZsHpuaAk3Hh1q0uNb_6hGTpuwBIrsp2z9U2T0oC0%3D&e2e=v%3D1%26x3dh%3DMEIwBQYDK2VvAzkAcz6jJk71InuxA0bOX7OUhddfB8Ov7xwQIlIDeXBRZaOntUU4brU5Y3rBzroZBdQJi0FKdtt_D7I%3D%2CMEIwBQYDK2VvAzkA-hDvk1duBi1hlOr08VWSI-Ou4JNNSQjseY69QyKm7Kgg1zZjbpGfyBqSZ2eqys6xtoV4ZtoQUXQ%3D")
    }
}
