import Foundation

final class InstallHelperService: NSObject, InstallHelperProtocol {
    func install(from sourcePath: String, to destinationPath: String, withReply reply: @escaping (String?) -> Void) {
        do {
            try InstallCopy.perform(from: sourcePath, to: destinationPath)
            reply(nil)
        } catch {
            reply(error.localizedDescription)
        }
    }
}

final class InstallHelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: InstallHelperProtocol.self)
        connection.exportedObject = InstallHelperService()
        connection.resume()
        return true
    }
}

let delegate = InstallHelperDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
