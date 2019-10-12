//
//  ViewController.swift
//  TextDetection
//
//  Created by Michael on 24/9/2019.
//  Copyright © 2019 Design Quest Limited. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - Properties
    
    var cameraOrientation = CGImagePropertyOrientation.right
    var session = AVCaptureSession()
    var requests = [VNRequest]()
    var capteredBuffer:CVImageBuffer?
    
    // MARK: - Config
    
    var sessionPreset = AVCaptureSession.Preset.high // change the capture quality here

    // MARK - Outlets
    
    @IBOutlet weak var videoImageView: UIImageView!
    @IBOutlet weak var infoView: UIView!
    @IBOutlet weak var corppedImageView: UIImageView!

    // MARK: - Override
    
    override func viewDidLoad() {
        super.viewDidLoad()
        startVideoSession()
        startDetection()
    }
    
    // MARK: - Video session
    
    private func startVideoSession() {
        if (!session.isRunning) {
            session.sessionPreset = self.sessionPreset
            let captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
            let deviceInput = try! AVCaptureDeviceInput(device: captureDevice!)
            session.addInput(deviceInput)
            
            let deviceOutput = AVCaptureVideoDataOutput()
            deviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
            session.addOutput(deviceOutput)
            
            let videoLayer = AVCaptureVideoPreviewLayer(session: session)
            videoLayer.frame = videoImageView.bounds
            videoImageView.layer.addSublayer(videoLayer)
            
            session.startRunning()
        }
    }

    // MARK: - Delegate
    
    // AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        self.capteredBuffer = pixelBuffer
        var requestOptions:[VNImageOption : Any] = [:]
        if let camData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics:camData]
        }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation.right, options: requestOptions)
        do {
            try imageRequestHandler.perform(self.requests) // pass the analysis requests here
        } catch {
            print(error)
        }
    }
    
    
    
    // MARK: - Detection
    
    private func startDetection() {
        let request = VNRecognizeTextRequest(completionHandler: self.detectionHandler)
        
        self.requests = [request]
    }
    
    private func detectionHandler(request: VNRequest, error: Error?) {
        guard let results = request.results else { return }
        let observations = results.map({$0 as! VNRecognizedTextObservation})
        
        DispatchQueue.main.async() {
            
            let targetFrame = self.infoView.bounds
            
            // Remove all sublayers of infoView
            self.infoView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

            for ob in observations {
                
                // Fill the detected area
                let area = self.drawArea(observation: ob, targetFrame: targetFrame)
                self.infoView.layer.addSublayer(area)
                
                // Draw the bounding box
                let rect = self.getBoundingBox(boundingBox: ob.boundingBox, targetFrame: targetFrame)
                self.infoView.layer.addSublayer(rect)
                
                //
                guard let recognizedText = ob.topCandidates(1).first else { break }
                if recognizedText.confidence > 0.9 {
                    print(recognizedText.string)
                }
            }
            
            guard let ob = observations.first else { return }
            
            // Crop the dected area (testing)
            guard let capteredBuffer = self.capteredBuffer else { return }
            let ciImage = CIImage(cvPixelBuffer: capteredBuffer)
                .oriented(forExifOrientation: Int32(self.cameraOrientation.rawValue))
            let imageSize = ciImage.extent.size
            let boundingBox = ob.boundingBox.scaled(to: imageSize)
            let topLeft = ob.topLeft.scaled(to: imageSize)
            let topRight = ob.topRight.scaled(to: imageSize)
            let bottomLeft = ob.bottomLeft.scaled(to: imageSize)
            let bottomRight = ob.bottomRight.scaled(to: imageSize)
            let correctedImage = ciImage
                .cropped(to: boundingBox)
                .applyingFilter("CIPerspectiveCorrection", parameters: [
                    "inputTopLeft": CIVector(cgPoint: topLeft),
                    "inputTopRight": CIVector(cgPoint: topRight),
                    "inputBottomLeft": CIVector(cgPoint: bottomLeft),
                    "inputBottomRight": CIVector(cgPoint: bottomRight)
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: 32
                ])
//                .applyingFilter("CIColorInvert")
            
            // Show the dected area for preview
            let image = UIImage(ciImage: correctedImage)
            self.corppedImageView.image = image
        }
    }
    
    // MARK: - Drawing
    
    // draw the detected area
    private func drawArea(observation ob:VNRectangleObservation, targetFrame: CGRect) -> CAShapeLayer {
        let rectangle = UIBezierPath()
        let width = targetFrame.width
        let height = targetFrame.height
        rectangle.move(to: CGPoint(x: width  * ob.topLeft.x, y: height * (1-ob.topLeft.y)))
        rectangle.addLine(to: CGPoint(x: width * ob.topRight.x, y: height * (1-ob.topRight.y)))
        rectangle.addLine(to: CGPoint(x: width * ob.bottomRight.x, y: height * (1-ob.bottomRight.y)))
        rectangle.addLine(to: CGPoint(x: width * ob.bottomLeft.x, y: height * (1-ob.bottomLeft.y)))
        rectangle.close()
        let rec = CAShapeLayer()
        rec.path = rectangle.cgPath
        rec.fillColor = UIColor.red.cgColor
        rec.borderColor = UIColor.red.cgColor
        rec.opacity = 0.3
        return rec
    }
    
    // create a bounding box layer
    private func getBoundingBox(boundingBox:CGRect, targetFrame: CGRect) -> CALayer {
        let frame = self.scaleBoundingBox(boundingBox: boundingBox, targetFrame: targetFrame)
        let layer = CALayer()
        layer.frame = frame
        layer.borderColor = UIColor.red.cgColor
        layer.borderWidth = 1
        return layer
    }
    
    // Scale boundingBox to target frame
    private func scaleBoundingBox(boundingBox:CGRect, targetFrame: CGRect) -> CGRect {
        let width = CGFloat(targetFrame.width)
        let height = CGFloat(targetFrame.height)
        let rect = CGRect(
            x: width * boundingBox.origin.x,
            y: height * (1 - boundingBox.origin.y - boundingBox.height),
            width: width * boundingBox.width,
            height: height * boundingBox.height)
        return rect
    }

}

