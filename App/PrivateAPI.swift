import Foundation

enum PrivateFramework {
    case skyLight
    case login
    case loaded

    private var handle: UnsafeMutableRawPointer? {
        switch self {
        case .skyLight: dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        case .login: dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
        case .loaded: UnsafeMutableRawPointer(bitPattern: -2)
        }
    }

    func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else {
            log.error("missing symbol \(name, privacy: .public) in \(String(describing: self), privacy: .public)")
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }
}
