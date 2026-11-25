import Foundation
import NotchCompressorCore

var response: ImageWorkerResponse
do {
    let args = CommandLine.arguments
    guard args.count == 4, let quality = Double(args[3]), quality.isFinite else {
        throw CompressionError.localized(.init("error.imageStructure"))
    }
    try ImageCompressionWorker.compress(
        input: URL(fileURLWithPath: args[1]), output: URL(fileURLWithPath: args[2]), quality: quality)
    response = ImageWorkerResponse(error: nil)
} catch {
    response = ImageWorkerResponse(error: (error as? CompressionError)?.localizedMessage ?? .init("error.imageWrite"))
}
FileHandle.standardOutput.write(try JSONEncoder().encode(response))
