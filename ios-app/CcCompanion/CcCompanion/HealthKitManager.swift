import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    @Published var authorized: Bool = false
    @Published var stepsToday: Int = 0
    @Published var activeCalToday: Double = 0
    @Published var exerciseMinToday: Double = 0
    @Published var standHoursToday: Int = 0
    @Published var latestHeartRate: Double? = nil
    @Published var restingHeartRate: Double? = nil
    @Published var sleepHoursLastNight: Double? = nil
    @Published var heartRateMin24h: Double? = nil
    @Published var heartRateMax24h: Double? = nil
    @Published var walkingDistance: Double = 0
    @Published var cycleDay: Int? = nil
    @Published var daysUntilNextPeriod: Int? = nil
    @Published var lastPeriodStart: Date? = nil

    private let readTypes: Set<HKObjectType> = {
        var s = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .heartRate) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) { s.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { s.insert(t) }
        if let t = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { s.insert(t) }
        if let t = HKCategoryType.categoryType(forIdentifier: .appleStandHour) { s.insert(t) }
        if let t = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) { s.insert(t) }
        return s
    }()

    func requestAuth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            authorized = true
        } catch {
            authorized = false
        }
    }

    func refreshAll() async {
        guard authorized else { return }
        async let s = fetchSteps()
        async let c = fetchActiveCal()
        async let e = fetchExerciseMin()
        async let h = fetchLatestHR()
        async let r = fetchRestingHR()
        async let sl = fetchSleep()
        async let hr = fetchHRRange()
        async let d = fetchDistance()
        async let st = fetchStandHours()
        async let cy = fetchCycleStats()
        let (sv, cv, ev, hv, rv, slv, hrv, dv, stv, cyv) = await (s, c, e, h, r, sl, hr, d, st, cy)
        stepsToday = sv
        activeCalToday = cv
        exerciseMinToday = ev
        latestHeartRate = hv
        restingHeartRate = rv
        sleepHoursLastNight = slv
        if let hrv { heartRateMin24h = hrv.0; heartRateMax24h = hrv.1 }
        walkingDistance = dv
        standHoursToday = stv
        cycleDay = cyv?.day
        daysUntilNextPeriod = cyv?.daysUntil
        lastPeriodStart = cyv?.lastStart
    }

    func summaryDict() -> [String: Any] {
        var d: [String: Any] = [
            "steps": stepsToday,
            "active_cal": Int(activeCalToday),
            "exercise_min": Int(exerciseMinToday),
            "stand_hours": standHoursToday,
            "distance_km": round(walkingDistance / 1000 * 100) / 100,
        ]
        if let hr = latestHeartRate { d["heart_rate"] = Int(hr) }
        if let rhr = restingHeartRate { d["resting_hr"] = Int(rhr) }
        if let sl = sleepHoursLastNight { d["sleep_hours"] = round(sl * 10) / 10 }
        if let lo = heartRateMin24h { d["hr_min_24h"] = Int(lo) }
        if let hi = heartRateMax24h { d["hr_max_24h"] = Int(hi) }
        if let day = cycleDay { d["cycle_day"] = day }
        if let until = daysUntilNextPeriod { d["days_until_period"] = until }
        return d
    }

    // MARK: - Queries

    private func todayInterval() -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (start, Date())
    }

    private func fetchSteps() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let (start, end) = todayInterval()
        return Int(await sumQuery(type: type, start: start, end: end, unit: .count()))
    }

    private func fetchActiveCal() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let (start, end) = todayInterval()
        return await sumQuery(type: type, start: start, end: end, unit: .kilocalorie())
    }

    private func fetchExerciseMin() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return 0 }
        let (start, end) = todayInterval()
        return await sumQuery(type: type, start: start, end: end, unit: .minute())
    }

    private func fetchDistance() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return 0 }
        let (start, end) = todayInterval()
        return await sumQuery(type: type, start: start, end: end, unit: .meter())
    }

    private func fetchLatestHR() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        return await latestSample(type: type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    private func fetchRestingHR() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        return await latestSample(type: type, unit: HKUnit.count().unitDivided(by: .minute()))
    }

    private func fetchStandHours() async -> Int {
        guard let type = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else { return 0 }
        let (start, end) = todayInterval()
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let count = (samples as? [HKCategorySample])?.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }.count ?? 0
                cont.resume(returning: count)
            }
            store.execute(q)
        }
    }

    private func fetchSleep() async -> Double? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .hour, value: -24, to: now)!
        let pred = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                guard let sleeps = samples as? [HKCategorySample] else {
                    cont.resume(returning: nil); return
                }
                let asleep = sleeps.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                }
                let total = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: total > 0 ? total / 3600 : nil)
            }
            store.execute(q)
        }
    }

    private func fetchHRRange() async -> (Double, Double)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let hrs = samples as? [HKQuantitySample], !hrs.isEmpty else {
                    cont.resume(returning: nil); return
                }
                let vals = hrs.map { $0.quantity.doubleValue(for: unit) }
                cont.resume(returning: (vals.min()!, vals.max()!))
            }
            store.execute(q)
        }
    }

    // MARK: - Cycle

    private struct CycleStats { let lastStart: Date; let day: Int; let daysUntil: Int }
    private let cycleAvgDays = 35

    private func fetchCycleStats() async -> CycleStats? {
        guard let type = HKCategoryType.categoryType(forIdentifier: .menstrualFlow) else { return nil }
        let cal = Calendar.current
        let lookback = cal.date(byAdding: .month, value: -6, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: lookback, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, _ in
                guard let cats = (samples as? [HKCategorySample])?.filter({
                    $0.value != HKCategoryValueMenstrualFlow.none.rawValue
                }), !cats.isEmpty else {
                    cont.resume(returning: nil); return
                }
                // most-recent cluster: walk newest→older, stop when gap > 5 days
                var lastStart = cats[0].startDate
                for s in cats.dropFirst() {
                    let gap = cal.dateComponents([.day], from: s.startDate, to: lastStart).day ?? Int.max
                    if gap > 5 { break }
                    lastStart = s.startDate
                }
                let today = cal.startOfDay(for: Date())
                let startDay = cal.startOfDay(for: lastStart)
                let day = (cal.dateComponents([.day], from: startDay, to: today).day ?? 0) + 1
                let nextPeriod = cal.date(byAdding: .day, value: self.cycleAvgDays, to: startDay) ?? today
                let daysUntil = cal.dateComponents([.day], from: today, to: nextPeriod).day ?? 0
                cont.resume(returning: CycleStats(lastStart: startDay, day: day, daysUntil: daysUntil))
            }
            store.execute(q)
        }
    }

    // MARK: - Helpers

    private func sumQuery(type: HKQuantityType, start: Date, end: Date, unit: HKUnit) async -> Double {
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func latestSample(type: HKQuantityType, unit: HKUnit) async -> Double? {
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: val)
            }
            store.execute(q)
        }
    }
}
