//
//  CurrentExchangeRates.swift
//  Balance
//
//  Created by Benjamin Baron on 10/16/17.
//  Copyright © 2017 Balanced Software, Inc. All rights reserved.
//

import Foundation

class CurrentExchangeRates {
    
    fileprivate struct Rate {
        let from: Currency
        let to: Currency
        let rate: Double
        var key: String {
            return "\(from.code)-\(to.code)"
        }
    }
    
    struct Notifications {
        static let exchangeRatesUpdated = Notification.Name("exchangeRatesUpdated")
    }
    
    private let exchangeRatesUrl = URL(string: "https://exchangerates.balancemy.money/exchangeRates")!
    private var isUpdatingExchangeRates = false
    
    private let cache = SimpleCache<ExchangeRateSource, [ExchangeRate]>()
    private let cachedRates = SimpleCache<String, Rate>()
    private let persistedFileName = "currentExchangeRates.data"
    private var persistedFileUrl: URL {
        return appSupportPathUrl.appendingPathComponent(persistedFileName)
    }
    
    func exchangeRates(forSource source: ExchangeRateSource) -> [ExchangeRate]? {
        return cache.get(valueForKey: source)
    }
    
    func allExchangeRates() -> [ExchangeRate]? {
        return cache.getAll().flatMap({$0.value}) as [ExchangeRate]?
    }
    
    func convertTicker(amount: Double, from: Currency, to: Currency) -> Double? {
        // TODO: Fix MIOTA conversions properly, no time for 1.0 release
        var fromCode = from.code
        switch from {
        case .crypto(let crypto):
            if crypto == .miota {
                fromCode = "IOT"
            }
        default:
            break
        }
        
        if from == to { return 1 }
        if let exchangeRate = cachedRates.get(valueForKey: "\(from.code)-\(to.code)") {
            return amount * exchangeRate.rate
        } else {
            for masterCurrency in ExchangeRateSource.mainCurrencies {
                if let fromRate = cachedRates.get(valueForKey: "\(fromCode)-\(masterCurrency.code)"), let toRate = cachedRates.get(valueForKey: "\(masterCurrency.code)-\(to.code)") {
                    return amount * fromRate.rate * toRate.rate
                }
            }
            guard let rateBTC = cachedRates.get(valueForKey: "\(fromCode)-\(Currency.btc.code)") else {
                return nil
            }
            if let finalRate = cachedRates.get(valueForKey: "\(Currency.usd.code)-\(to.code)"), let dollarRate = cachedRates.get(valueForKey: "\(Currency.btc.code)-\(Currency.usd.code)") {
                return amount * rateBTC.rate * dollarRate.rate * finalRate.rate
            } else if let finalRate = cachedRates.get(valueForKey: "\(Currency.eth.code)-\(to.code)"), let etherRate = cachedRates.get(valueForKey: "\(Currency.btc.code)-\(Currency.eth.code)") {
                return amount * rateBTC.rate * etherRate.rate * finalRate.rate
            }
        }
        return nil
    }
    
    func convert(amount: Int, from: Currency, to: Currency, source: ExchangeRateSource) -> Int? {
        let doubleAmount = Double(amount) / pow(10, Double(from.decimals))
        if let doubleConvertedAmount = convert(amount: doubleAmount, from: from, to: to, source: source) {
            let intConvertedAmount = Int(doubleConvertedAmount * pow(10, Double(to.decimals)))
            return intConvertedAmount
        }
        return nil
    }
    
    public func convert(amount: Double, from: Currency, to: Currency, source: ExchangeRateSource) -> Double? {
        var rate: Double?
        
        if let newRate = directConvert(amount: amount, from: from, to: to, source: source) {
            return newRate
        }
        for source in ExchangeRateSource.all {
            if let newRate = directConvert(amount: amount, from: from, to: to, source: source) {
                rate = newRate
            }
            if rate != nil {
                return rate!
            } else {
                //change currency and loop through all sources to get a connecting currency to use as middle point
                for currency in ExchangeRateSource.mainCurrencies {
                    var fromRate: Double? = getRate(from: from, to: currency, source: source)
                    var toRate: Double? = getRate(from: currency, to: to, source: source)
                    for source in ExchangeRateSource.all {
                        if currency == from || currency == to {
                            continue
                        }
                        if fromRate == nil, let newfromRate = getRate(from: from, to: currency, source: source) {
                            fromRate = newfromRate
                        }
                        
                        if toRate == nil, let newtoRate = getRate(from: currency, to: to, source: source) {
                            toRate = newtoRate
                        }
                        if fromRate != nil && toRate != nil {
                            return amount * fromRate! * toRate!
                        }
                    }
                }
            }
        }
        
        // If we fail to convert, then use the non-source-specific convertTicker function
        return convertTicker(amount: amount, from: from, to: to)
    }
    
    public func directConvert(amount: Double, from: Currency, to: Currency, source: ExchangeRateSource) -> Double? {
        if let rate = getRate(from: from, to: to, source: source) {
            return amount * rate
        }
        return nil
    }
    
    public func getRate(from: Currency, to: Currency, source: ExchangeRateSource) -> Double? {
        if source == .average {
            return convertTicker(amount: 1, from: from, to: to)
        }
        if let exchangeRates = exchangeRates(forSource: source) {
            // First check if the exact rate exists (either directly or reversed)
            if let rate = exchangeRates.rate(from: from, to: to) {
                return rate
            } else if let rate = exchangeRates.rate(from: to, to: from) {
                return (1.0 / rate)
            }
        }
        
        return nil
    }
    
    func updateExchangeRates() {
        guard !isUpdatingExchangeRates else {
            log.debug("updateExchangeRates called but already updating so returning")
            return
        }
        
        log.debug("Updating exchange rates")
        isUpdatingExchangeRates = true
        let task = certValidatedSession.dataTask(with: exchangeRatesUrl) { maybeData, maybeResponse, maybeError in
            // Make sure there's data
            guard let data = maybeData, maybeError == nil else {
                log.error("Error updating exchange rates, either no data or error: \(String(describing: maybeError))")
                self.isUpdatingExchangeRates = false
                return
            }
            
            // Parse and cache the data
            if self.parse(data: data) {
                self.persist(data: data)
                NotificationCenter.postOnMainThread(name: Notifications.exchangeRatesUpdated)
            }
            
            self.isUpdatingExchangeRates = false
            log.debug("Exchange rates updated")
        }
        task.resume()
    }
    
    fileprivate func average(rates:[ExchangeRate]) -> Double? {
        guard rates.count > 0 else { return nil }
        let groupedRates = rates.map({$0.rate})
        let averageRate = groupedRates.reduce(0, +)/Double(groupedRates.count)
        return averageRate
    }
    
    @discardableResult func parse(data: Data) -> Bool {
        // Try to parse the JSON
        guard let tryExchangeRatesJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let exchangeRatesJson = tryExchangeRatesJson, exchangeRatesJson["code"] as? Int == BalanceError.success.rawValue else {
            log.error("Error parsing exchange rates, failed to parse json data")
            analytics.trackEvent(withName: "Failed to parse exchange rates")
            return false
        }
        
        // Parse the rates
        for (key, value) in exchangeRatesJson {
            // Ensure the exchange rate source is valid
            guard let sourceRaw = Int(key), let source = ExchangeRateSource(rawValue: sourceRaw) else {
                continue
            }
            
            // Ensure the value contains rates
            guard let value = value as? [String: Any], let rates = value["rates"] as? [[String: Any]] else {
                continue
            }
            
            // Parse the exchange rates
            var exchangeRates = [ExchangeRate]()
            for rateGroup in rates {
                if let from = rateGroup["from"] as? String, let to = rateGroup["to"] as? String, let rate = rateGroup["rate"] as? Double {
                    let exchangeRate = ExchangeRate(source: source, from: Currency.rawValue(from), to: Currency.rawValue(to), rate: rate)
                    exchangeRates.append(exchangeRate)
                }
            }
            
            // Cache the updated exchange rates
            if exchangeRates.count > 0 {
                self.cache.set(value: exchangeRates, forKey: source)
            }
        }
      
        let tempCachedRates = SimpleCache<String, Rate>()
        let allRates = self.cache.getAll().flatMap({$0.value})

        //create hash of exchanges averaging all exchanges rates
        for exchangeKey in self.cache.getAll().keys {
            for exchangeRate in self.cache.get(valueForKey: exchangeKey)! {
                if tempCachedRates.get(valueForKey: "\(exchangeRate.from.code)-\(exchangeRate.to.code)") != nil { continue }
                let sameRates = allRates.filter({$0.from == exchangeRate.from && $0.to == exchangeRate.to})
                guard let averageRate = self.average(rates: sameRates) else { continue }

                let rate = Rate(from: exchangeRate.from, to: exchangeRate.to, rate: averageRate)
                tempCachedRates.set(value: rate, forKey: rate.key)

                let opositeRate = Rate(from: exchangeRate.to, to: exchangeRate.from, rate: 1/exchangeRate.rate)
                tempCachedRates.set(value: opositeRate, forKey: opositeRate.key)
            }
        }
        self.cachedRates.replaceAll(values: tempCachedRates.getAll())
        
        return true
    }
    
    @discardableResult func persist(data: Data) -> Bool {
        do {
            try data.write(to: persistedFileUrl, options: .atomicWrite)
            return true
        } catch {
            log.error("Failed to persist current exchange rates: \(error)")
            return false
        }
    }
    
    @discardableResult func load() -> Bool {
        do {
            let data = try Data(contentsOf: persistedFileUrl)
            return parse(data: data)
        } catch {
            log.error("Failed to load current exchange rates from disk: \(error)")
            return false
        }
    }
}
