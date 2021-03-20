/* 
  AtomicWrapper.swift
  CCLocation

  Created by TCode on 20/03/2021.
  Copyright © 2021 Crowd Connected. All rights reserved.
*/

import Foundation

@propertyWrapper
public struct Atomic<Value> {
  private let queue = DispatchQueue(label: "colocator.storeState.serial.queue.\(UUID().uuidString)")
  private var value: Value

  public init(wrappedValue: Value) {
    self.value = wrappedValue
  }

  public var wrappedValue: Value {
    get {
      return queue.sync { value }
    }
    set {
      queue.sync { value = newValue }
    }
  }
}
