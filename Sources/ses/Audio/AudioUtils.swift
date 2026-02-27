import AVFoundation
import Foundation

public func rmsDbFS(_ samples: [Int16]) -> Double {
    if samples.isEmpty { return -160.0 }
    var sumSquares: Double = 0
    let scale = 1.0 / Double(Int16.max)
    for s in samples {
        let x = Double(s) * scale
        sumSquares += x * x
    }
    let mean = sumSquares / Double(samples.count)
    let rms = sqrt(mean)
    if rms <= 0 { return -160.0 }
    return 20.0 * log10(rms)
}

public func streamBasicDescription(from sampleBuffer: CMSampleBuffer)
    -> AudioStreamBasicDescription?
{
    guard let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
    guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmt) else { return nil }
    return asbdPtr.pointee
}

public func extractInt16Interleaved(from sampleBuffer: CMSampleBuffer) -> [Int16]? {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
    var length = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    CMBlockBufferGetDataPointer(
        blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
        dataPointerOut: &dataPointer)
    guard length > 0 else { return nil }
    guard let ptr = dataPointer else { return nil }
    let count = length / MemoryLayout<Int16>.size
    return ptr.withMemoryRebound(to: Int16.self, capacity: count) {
        Array(UnsafeBufferPointer(start: $0, count: count))
    }
}

public func downmixToMono(interleaved: [Int16], channels: Int) -> [Int16] {
    guard channels > 1 else { return interleaved }
    let frames = interleaved.count / channels
    if frames <= 0 { return [] }
    var mono: [Int16] = []
    mono.reserveCapacity(frames)
    for i in 0..<frames {
        mono.append(interleaved[i * channels])  // take ch0
    }
    return mono
}
