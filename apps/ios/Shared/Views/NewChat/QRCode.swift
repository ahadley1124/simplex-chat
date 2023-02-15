//
//  QRCode.swift
//  SimpleX
//
//  Created by Evgeny Poberezkin on 30/01/2022.
//  Copyright © 2022 SimpleX Chat. All rights reserved.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct MutableQRCode: View {
    @Binding var uri: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image = image {
                qrCodeImage(image)
            }
        }
        .onAppear {
            image = generateImage(uri)
        }
        .onChange(of: uri) { _ in
            image = generateImage(uri)
        }
    }
}

struct QRCode: View {
    let uri: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image = image {
                qrCodeImage(image)
            }
        }
        .onAppear {
            image = image ?? generateImage(uri)
        }
    }
}

private func qrCodeImage(_ image: UIImage) -> some View {
    Image(uiImage: image)
        .resizable()
        .interpolation(.none)
        .aspectRatio(1, contentMode: .fit)
        .textSelection(.enabled)
}

private func generateImage(_ uri: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(uri.utf8)
    if let outputImage = filter.outputImage,
       let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
        return UIImage(cgImage: cgImage)
    }
    return nil
}

struct QRCode_Previews: PreviewProvider {
    static var previews: some View {
        QRCode(uri: "https://simplex.chat/invitation#/?v=1&smp=smp%3A%2F%2Fu2dS9sG8nMNURyZwqASV4yROM28Er0luVTx5X1CsMrU%3D%40smp4.simplex.im%2FFe5ICmvrm4wkrr6X1LTMii-lhBqLeB76%23MCowBQYDK2VuAyEAdhZZsHpuaAk3Hh1q0uNb_6hGTpuwBIrsp2z9U2T0oC0%3D&e2e=v%3D1%26x3dh%3DMEIwBQYDK2VvAzkAcz6jJk71InuxA0bOX7OUhddfB8Ov7xwQIlIDeXBRZaOntUU4brU5Y3rBzroZBdQJi0FKdtt_D7I%3D%2CMEIwBQYDK2VvAzkA-hDvk1duBi1hlOr08VWSI-Ou4JNNSQjseY69QyKm7Kgg1zZjbpGfyBqSZ2eqys6xtoV4ZtoQUXQ%3D")
    }
}
