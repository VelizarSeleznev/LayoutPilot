import Foundation

enum GlobeKeyAction: Equatable {
    case passThrough
    case consume
    case consumeAndCycle
}

struct GlobeKeyStateMachine {
    private(set) var isGlobeDown = false

    mutating func handle(isGlobeEvent: Bool, isDown: Bool, isEnabled: Bool) -> GlobeKeyAction {
        guard isEnabled else {
            isGlobeDown = false
            return .passThrough
        }

        guard isGlobeEvent else {
            return .passThrough
        }

        if isDown {
            guard !isGlobeDown else {
                return .consume
            }
            isGlobeDown = true
            return .consumeAndCycle
        }

        isGlobeDown = false
        return .consume
    }

    mutating func reset() {
        isGlobeDown = false
    }
}

final class InstantInputSourceCycler: @unchecked Sendable {
    private let client: InputSourceClient
    private let lock = NSLock()
    private var cachedSources: [InputSourceInfo] = []

    init(client: InputSourceClient = SystemInputSourceClient()) {
        self.client = client
    }

    @discardableResult
    func refreshSources() -> [InputSourceInfo] {
        let sources = client.availableInputSources()
        lock.lock()
        cachedSources = sources
        lock.unlock()
        return sources
    }

    func cycleToNextSource() throws -> InputSourceInfo? {
        var sources = sourceSnapshot()
        guard sources.count > 1 else {
            return nil
        }

        let currentSourceID = client.currentInputSourceID()
        var target = targetSource(in: sources, currentSourceID: currentSourceID)

        if currentSourceID == nil || !sources.contains(where: { $0.sourceID == currentSourceID }) {
            sources = refreshSources()
            guard sources.count > 1 else {
                return nil
            }
            target = targetSource(in: sources, currentSourceID: currentSourceID)
        }

        do {
            try client.activateInputSource(withID: target.sourceID)
            return target
        } catch {
            sources = refreshSources()
            guard sources.count > 1 else {
                throw error
            }
            let retryTarget = targetSource(
                in: sources,
                currentSourceID: client.currentInputSourceID()
            )
            try client.activateInputSource(withID: retryTarget.sourceID)
            return retryTarget
        }
    }

    private func sourceSnapshot() -> [InputSourceInfo] {
        lock.lock()
        defer { lock.unlock() }
        return cachedSources
    }

    private func targetSource(
        in sources: [InputSourceInfo],
        currentSourceID: String?
    ) -> InputSourceInfo {
        guard let currentSourceID,
              let currentIndex = sources.firstIndex(where: { $0.sourceID == currentSourceID }) else {
            return sources[0]
        }
        return sources[(currentIndex + 1) % sources.count]
    }
}
