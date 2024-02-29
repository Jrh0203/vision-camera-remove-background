import VisionCamera
import AVFoundation
import CoreMedia
import Vision
import CoreImage.CIFilterBuiltins

//extension UIImage {
//  var base64: String? {
//    self.jpegData(compressionQuality: 1)?.base64EncodedString()
//  }
//}

extension UIImage {
  var base64: String? {
    self.pngData()?.base64EncodedString()
  }
}

@objc(VisionCameraFaceDetector)
public class VisionCameraFaceDetector: FrameProcessorPlugin {
  public override init(proxy: VisionCameraProxyHolder, options: [AnyHashable: Any]! = [:]) {
    super.init(proxy: proxy, options: options)
  }
  
  private func processVideoFrame(_ framePixelBuffer: CVPixelBuffer)  -> UIImage? {
    var segmentationRequest = VNGeneratePersonSegmentationRequest()
    segmentationRequest.qualityLevel = .balanced
    segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    
    let requestHandler = VNSequenceRequestHandler()
    // Perform the requests on the pixel buffer that contains the video frame.
    try? requestHandler.perform([segmentationRequest],
                                on: framePixelBuffer,
                                orientation: .right)
    
    // Get the pixel buffer that contains the mask image.
    guard let maskPixelBuffer =
            segmentationRequest.results?.first?.pixelBuffer else { return nil}
    
    // Process the images.
    return blend(original: framePixelBuffer, mask: maskPixelBuffer)
  }
  
  func saveImageAsync(_ image: UIImage, frameIndex: Int) -> String {
      let fileName = "image-\(frameIndex)" // Constructing filename with frameIndex
      let url = FileManager.default.temporaryDirectory
                              .appendingPathComponent(fileName)
                              .appendingPathExtension("png")
      
      // Move the file writing operation to a background queue
      DispatchQueue.global(qos: .background).async {
          if let pngData = image.pngData() {
              do {
                  try pngData.write(to: url)
              } catch {
                  print("Error saving image: \(error)")
              }
          }
      }
      
      // Return the URL path immediately, without waiting for the async operation
      return url.path
  }

  
  private func blend(original framePixelBuffer: CVPixelBuffer,
                     mask maskPixelBuffer: CVPixelBuffer)  -> UIImage? {
    
    
    // Create CIImage objects for the video frame and the segmentation mask.
    let originalImage = CIImage(cvPixelBuffer: framePixelBuffer).oriented(.right)
    var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
    
    // Scale the mask image to fit the bounds of the video frame.
    let scaleX = originalImage.extent.width / maskImage.extent.width
    let scaleY = originalImage.extent.height / maskImage.extent.height
    maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))
    
    
    // Blend the original, background, and mask images.
    let blendFilter = CIFilter.blendWithRedMask()
    blendFilter.inputImage = originalImage
    //        blendFilter.backgroundImage = backgroundImage
    blendFilter.maskImage = maskImage
    
    // Set the new, blended image as current.
    var currentCIImage = blendFilter.outputImage?.oriented(.left)
    
    let context = CIContext(options: nil)

    guard let currentCIImage = currentCIImage else { return nil }

    // Calculate the center, square crop dimensions.
    let contextSize = currentCIImage.extent.size
    let sideLength = min(contextSize.width, contextSize.height)
    let xOffset = (contextSize.width - sideLength) / 2.0
    let yOffset = (contextSize.height - sideLength) / 2.0
    let cropSquare = CGRect(x: xOffset, y: yOffset, width: sideLength, height: sideLength)

    // Create a cropped CIImage.
    let croppedCIImage = currentCIImage.cropped(to: cropSquare);

    // Convert the cropped CIImage to CGImage.
    guard let cgImage = context.createCGImage(croppedCIImage, from: croppedCIImage.extent) else { return nil }

    let output = UIImage(cgImage: cgImage)
    return output
  }
  
  
  public override func callback(_ frame: Frame, withArguments arguments: [AnyHashable: Any]?) -> Any? {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(frame.buffer) else { return "no image buffer" }
    
    let frameIndex = arguments?["frameIndex"] as? Int
    
    // Since we're in a synchronous function, use Task and continuation to call async function
    do {
      let processedImage = try processVideoFrame(imageBuffer)
      guard let processedImage = processedImage else {
        return ["error": "Failed to process image"]
      }
      
      let fileOutput = saveImageAsync(processedImage, frameIndex: frameIndex!)

      return ["uri": fileOutput]
//      let base64String = processedImage.base64
//      return [base64String]
//      return [frameIndex]
    } catch {
      return ["error": "Error processing image: \(error)"]
    }
  }
  
}
