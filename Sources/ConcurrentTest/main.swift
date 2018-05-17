import Foundation
import AppKit
import ReactiveSwift
import enum Result.NoError

// Just grab the default desktop images
let imagePath = URL(fileURLWithPath: "/Library/Desktop Pictures")
let pathURLs = try FileManager.default.contentsOfDirectory(at: imagePath, includingPropertiesForKeys: [], options: []).filter { $0.pathExtension == "jpg" }

// Multiply by the number of images to demonstrate the issue (this comes out to 360 on my system)
let imageURLs: [URL] = (0 ..< 10).flatMap { _ in return pathURLs }

// Returns a signal producer that performs its image rendering on a given queue.
// Defaults to the global concurrent queue, for demonstration purposes.
func processOneImage(fileURL: URL, on queue: DispatchQueue = DispatchQueue.global(qos: .userInitiated)) -> SignalProducer<CGImage, NoError> {
    return SignalProducer { observer, disposable in
        // There is absolutely nothing wrong with doing your SignalProducer's
        // work on a background queue, as shown:
        print("Scheduling SignalProducer for \(fileURL)")
        queue.async {
            let image = NSImage(contentsOf: fileURL)
            let renderedImage = NSImage(size: CGSize(width: 512, height: 512), flipped: false) { rect -> Bool in
                print("Rendering \(fileURL)")
                image?.draw(in: rect)
                return true
            }
            
            // We return the CGImage here in order to force the render callback
            // above to actually run.
            if let cgImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                observer.send(value: cgImage)
            }
            observer.sendCompleted()
        }
    }
}

// Adjust this value to 'true' and we'll cap the concurrency used by flatMap.
// Without using this mechanism, *every call* to processOneImage will be
// scheduled, and will execute all at once. DispatchQueue will *not* throttle
// the # of threads based on the CPU threads you have on your system.
//
// Note: Choosing 'true' may completely lock up your machine. If you pause in
// the debugger, you will see many more threads than you have CPUs in your
// system.
let goCrazyWithThreads = false
let threadLimit: UInt = UInt(ProcessInfo.processInfo.activeProcessorCount)
let strategy = goCrazyWithThreads ? FlattenStrategy.merge : FlattenStrategy.concurrent(limit: threadLimit)

// Builds a producer that processes all the images in a given list
let producer = SignalProducer(imageURLs)
    .flatMap(strategy) { processOneImage(fileURL: $0) }

var images: [CGImage] = []
let results = producer.collect().on(value: { images = $0 }).wait()

print("Processed \(images.count) images")
