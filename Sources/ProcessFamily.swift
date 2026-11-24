import Foundation

struct ProcessIdentity: Hashable {
    let pid: Int32
    let parentPID: Int32
    let born: UInt64

    var key: ProcessKey { ProcessKey(pid: pid, born: born) }
}

struct ProcessKey: Hashable {
    let pid: Int32
    let born: UInt64
}

func processFamily(root: ProcessKey, tracked: Set<ProcessKey>, identities: [ProcessIdentity], includeChildren: Bool) -> Set<ProcessKey> {
    let current = Dictionary(identities.map { ($0.pid, $0) }, uniquingKeysWith: { _, latest in latest })
    var alive = Set<ProcessKey>()
    if current[root.pid]?.key == root {
        alive.insert(root)
    }
    guard includeChildren else { return alive }
    for key in tracked where current[key.pid]?.key == key {
        alive.insert(key)
    }
    let childrenByParent = Dictionary(grouping: identities, by: \.parentPID)
    var queue = Array(alive)
    var index = 0
    while index < queue.count {
        let parent = queue[index]
        index += 1
        for child in childrenByParent[parent.pid] ?? [] where !alive.contains(child.key) {
            alive.insert(child.key)
            queue.append(child.key)
        }
    }
    return alive
}

func appBundlePrefix(_ path: String) -> String? {
    guard let match = path.range(of: ".app/", options: .caseInsensitive) else { return nil }
    return String(path[..<match.upperBound])
}
