//
//  PlaidCategory.swift
//  Balance
//
//  Created by Benjamin Baron on 7/14/17.
//  Copyright © 2017 Balanced Software, Inc. All rights reserved.
//

import Foundation

public struct PlaidCategory {
    
    public let id: String
    public let type: String
    
    public let hierarchy: [String]
    
    public init(category: [String: Any]) throws {
        id = try checkType(category["id"], name: "id")
        type = try checkType(category["type"], name: "type")
        
        hierarchy = try checkType(category["hierarchy"], name: "hierarchy")
    }
}
