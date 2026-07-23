import Foundation
import LayoutPilotCore
import OSLog

@MainActor
final class RemotePrankPackService {
    private static let manifestURL = URL(string: "https://raw.githubusercontent.com/VelizarSeleznev/LayoutPilot/main/docs/remote/friend-prank.json")!
    private static let checkInterval = Duration.seconds(15 * 60)
    private static let maxManifestBytes = 16 * 1024

    private let logger = Logger(
        subsystem: "com.velizard.LayoutPilot",
        category: "RemotePrankPackService"
    )
    private let store: LayoutPilotStore
    private var pollingTask: Task<Void, Never>?

    init(store: LayoutPilotStore) {
        self.store = store
    }

    func syncWithCurrentConfiguration() {
        if shouldAutoApplyPack {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard pollingTask == nil else { return }
        guard shouldAutoApplyPack else { return }

        pollingTask = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func run() async {
        while !Task.isCancelled {
            guard shouldAutoApplyPack else {
                stop()
                return
            }

            await checkForUpdate()

            guard shouldAutoApplyPack else {
                stop()
                return
            }

            do {
                try await Task.sleep(for: Self.checkInterval)
            } catch {
                break
            }
        }
    }

    private func checkForUpdate() async {
        guard shouldAutoApplyPack else { return }

        if let bundledManifest = bundledManifest() {
            switch store.applyRemotePrankPack(bundledManifest) {
            case .applied:
                logger.info("Applied bundled prank pack.")
                stop()
                return
            case .alreadyHandled, .disabled:
                stop()
                return
            case .invalidManifest:
                logger.error("Bundled prank manifest was invalid.")
            }
        }

        guard let remoteManifest = await fetchManifest() else { return }
        switch store.applyRemotePrankPack(remoteManifest) {
        case .applied:
            logger.info("Applied remote prank pack.")
            stop()
        case .alreadyHandled, .disabled:
            stop()
        case .invalidManifest:
            logger.notice("Remote prank manifest was invalid for this client.")
        }
    }

    private func bundledManifest() -> RemotePrankPackManifest? {
        guard let url = Bundle.main.url(forResource: "friend-prank", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              data.count <= Self.maxManifestBytes else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RemotePrankPackManifest.self, from: data)
    }

    private func fetchManifest() async -> RemotePrankPackManifest? {
        do {
            var request = URLRequest(url: Self.manifestURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.httpMethod = "GET"
            request.setValue("LayoutPilot", forHTTPHeaderField: "User-Agent")

            let session = URLSession(configuration: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpShouldSetCookies = false
                configuration.httpCookieAcceptPolicy = .never
                configuration.urlCache = nil
                configuration.urlCredentialStorage = nil
                configuration.timeoutIntervalForRequest = 8
                configuration.timeoutIntervalForResource = 8
                return configuration
            }())
            let (data, response) = try await session.data(for: request)

            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                return nil
            }
            guard data.count <= Self.maxManifestBytes else {
                logger.error("Remote prank manifest is larger than \(Self.maxManifestBytes) bytes.")
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(RemotePrankPackManifest.self, from: data)
        } catch {
            logger.debug("Remote prank manifest fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private var shouldAutoApplyPack: Bool {
        store.configuration.remotePrankPackEnabled
            && store.configuration.appliedRemotePrankPackID != RemotePrankPackPolicy.campaignID
    }
}
