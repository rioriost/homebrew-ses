import AVFoundation
import Foundation
import Speech
import sesCore

Task {
    let args = Args.parse()
    if args.mcp {
        await MCPServer().run(args: args)
    } else {
        await SesApp().run(args: args)
    }
}
dispatchMain()
