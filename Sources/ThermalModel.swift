import Foundation

struct Reading {
    let id: String
    let label: String
    let value: Double?
    let source: String
    var formatted: String { value.map { String(format: "%.0f °C", $0) } ?? "indisponible" }
}


struct AlertState {
    var hot = Set<String>()
    mutating func update(_ readings: [Reading], threshold: (Reading) -> Double) -> [Reading] {
        hot.formIntersection(Set(readings.map(\.id)))
        var newlyHot: [Reading] = []
        for reading in readings {
            guard let value = reading.value else { continue }
            if value >= threshold(reading), !hot.contains(reading.id) {
                hot.insert(reading.id); newlyHot.append(reading)
            } else if value <= threshold(reading) - 5 { hot.remove(reading.id) }
        }
        return newlyHot
    }
}

