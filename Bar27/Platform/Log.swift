import OSLog

extension Logger {
    init(category: String) {
        self.init(subsystem: Bundle.main.bundleIdentifier ?? "com.attila-krb.Bar27", category: category)
    }
}
