//
//  CIImageView.swift
//  SimpleX
//
//  Created by JRoberts on 12/04/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import SimpleXChat

struct CIImageView: View {
    @Environment(\.colorScheme) var colorScheme
    let chatItem: ChatItem
    let image: String
    let maxWidth: CGFloat
    @Binding var imgWidth: CGFloat?
    @State var scrollProxy: ScrollViewProxy?
    @State private var showFullScreenImage = false

    var body: some View {
        let file = chatItem.file
        VStack(alignment: .center, spacing: 6) {
            if let uiImage = getLoadedImage(file) {
                imageView(uiImage)
                .fullScreenCover(isPresented: $showFullScreenImage) {
                    FullScreenImageView(chatItem: chatItem, image: uiImage, showView: $showFullScreenImage, scrollProxy: scrollProxy)
                }
                .onTapGesture { showFullScreenImage = true }
            } else if let data = Data(base64Encoded: dropImagePrefix(image)),
                      let uiImage = UIImage(data: data) {
                imageView(uiImage)
                    .onTapGesture {
                        if let file = file {
                            switch file.fileStatus {
                            case .rcvInvitation:
                                Task {
                                    if let user = ChatModel.shared.currentUser {
                                        await receiveFile(user: user, fileId: file.fileId)
                                    }
                                    // TODO image accepted alert?
                                }
                            case .rcvAccepted:
                                AlertManager.shared.showAlertMsg(
                                    title: "Waiting for image",
                                    message: "Image will be received when your contact is online, please wait or check later!"
                                )
                            case .rcvTransfer: () // ?
                            case .rcvComplete: () // ?
                            case .rcvCancelled: () // TODO
                            default: ()
                            }
                        }
                    }
            }
        }
    }

    private func imageView(_ img: UIImage) -> some View {
        let w = img.size.width <= img.size.height ? maxWidth * 0.75 : img.imageData == nil ? .infinity : maxWidth
        DispatchQueue.main.async { imgWidth = w }
        return ZStack(alignment: .topTrailing) {
            if img.imageData == nil {
                Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: w)
            } else {
                SwiftyGif(image: img)
                        .frame(width: w, height: w * img.size.height / img.size.width)
                        .scaledToFit()
            }
            loadingIndicator()
        }
    }

    @ViewBuilder private func loadingIndicator() -> some View {
        if let file = chatItem.file {
            switch file.fileStatus {
            case .sndTransfer:
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 20, height: 20)
                    .tint(.white)
                    .padding(8)
            case .sndComplete:
                Image(systemName: "checkmark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .foregroundColor(.white)
                    .padding(13)
            case .rcvAccepted:
                Image(systemName: "ellipsis")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundColor(.white)
                    .padding(11)
            case .rcvTransfer:
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 20, height: 20)
                    .tint(.white)
                    .padding(8)
            default: EmptyView()
            }
        }
    }
}
