import AVFoundation
import Darwin
import Foundation
import Speech
import sesCore

Task {
    let args = Args.parse()
    if args.version {
        print(BuildVersion.value)
        exit(0)
    }
    if args.mcp {
        await MCPServer().run(args: args)
    } else {
        await SesApp().run(args: args)
    }
}
dispatchMain()
