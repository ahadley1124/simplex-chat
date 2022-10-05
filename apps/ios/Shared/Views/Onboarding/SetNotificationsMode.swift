//
//  NotificationsModeView.swift
//  SimpleX (iOS)
//
//  Created by Evgeny on 03/07/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct SetNotificationsMode: View {
    @EnvironmentObject var m: ChatModel
    @State private var notificationMode = NotificationsMode.instant
    @State private var showAlert: NotificationAlert?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Push notifications").font(.largeTitle)

                Text("Send notifications:")
                ForEach(NotificationsMode.values) { mode in
                    NtfModeSelector(mode: mode, selection: $notificationMode)
                }

                Spacer()

                Button {
                    if let token = m.deviceToken {
                        setNotificationsMode(token, notificationMode)
                    } else {
                        AlertManager.shared.showAlertMsg(title: "No device token!")
                    }
                    m.onboardingStage = .onboardingComplete
                } label: {
                    if case .off = notificationMode {
                        Text("Use chat")
                    } else {
                        Text("Enable notifications")
                    }
                }
                .font(.title)
                .frame(maxWidth: .infinity)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func setNotificationsMode(_ token: DeviceToken, _ mode: NotificationsMode) {
        switch mode {
        case .off:
            m.tokenStatus = .new
            m.notificationMode = .off
        default:
            Task {
                do {
                    let status = try await apiRegisterToken(token: token, notificationMode: mode)
                    await MainActor.run {
                        m.tokenStatus = status
                        m.notificationMode = mode
                    }
                } catch let error {
                    AlertManager.shared.showAlertMsg(
                        title: "Error enabling notifications",
                        message: "\(responseError(error))"
                    )
                }
            }
        }
    }
}

struct NtfModeSelector: View {
    var mode: NotificationsMode
    @Binding var selection: NotificationsMode
    @State private var tapped = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.label)
                    .font(.headline)
                    .foregroundColor(selection == mode ? .accentColor : .secondary)
                Text(ntfModeDescription(mode))
                    .lineLimit(10)
                    .font(.subheadline)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: tapped ? .secondarySystemFill : .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(selection == mode ? Color.accentColor : Color(uiColor: .secondarySystemFill), lineWidth: 2)
        )
        ._onButtonGesture { down in
            tapped = down
            if down { selection = mode }
        } perform: {}
    }
}

struct NotificationsModeView_Previews: PreviewProvider {
    static var previews: some View {
        SetNotificationsMode()
    }
}
