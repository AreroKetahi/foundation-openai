//
//  DeepSeekLanguageModel+Util.swift
//  foundation-deepseek
//
//  Created by Arkivili Collindort on 10/06/2026
//

import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit

package func FDSCGImageToPNGData(_ image: CGImage) -> Data? {
    UIImage(cgImage: image).pngData()
}
#elseif canImport(AppKit)
import AppKit
import UniformTypeIdentifiers

package func FDSCGImageToPNGData(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    
    CGImageDestinationAddImage(destination, image, nil)
    
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    
    return data as Data
}
#endif
