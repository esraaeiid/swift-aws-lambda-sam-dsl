// ===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
// ===----------------------------------------------------------------------===//

// This is based on Foundation's JSONEncoder
// https://github.com/apple/swift-corelibs-foundation/blob/main/Sources/Foundation/JSONEncoder.swift

import Foundation

/// A marker protocol used to determine whether a value is a `String`-keyed `Dictionary`
/// containing `Encodable` values
///
private protocol _YAMLStringDictionaryEncodableMarker {}

extension Dictionary: _YAMLStringDictionaryEncodableMarker where Key == String, Value: Encodable {}

// ===----------------------------------------------------------------------===//
// YAML Encoder
// ===----------------------------------------------------------------------===//

/// `YAMLEncoder` facilitates the encoding of `Encodable` values into YAML.
open class YAMLEncoder {
    // MARK: Options

    /// The formatting of the output YAML data.
    public struct OutputFormatting: OptionSet {
        /// The format's default value.
        public let rawValue: UInt

        /// Creates an OutputFormatting value with the given raw value.
        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        /// Produce human-readable YAML with indented output.
        //        public static let prettyPrinted = OutputFormatting(rawValue: 1 << 0)

        /// Produce JSON with dictionary keys sorted in lexicographic order.
        public static let sortedKeys = OutputFormatting(rawValue: 1 << 1)

        /// By default slashes get escaped ("/" → "\/", "http://apple.com/" → "http:\/\/apple.com\/")
        /// for security reasons, allowing outputted YAML to be safely embedded within HTML/XML.
        /// In contexts where this escaping is unnecessary, the YAML is known to not be embedded,
        /// or is intended only for display, this option avoids this escaping.
        public static let withoutEscapingSlashes = OutputFormatting(rawValue: 1 << 3)
    }

    /// The strategy to use for encoding `Date` values.
    public enum DateEncodingStrategy {
        /// Defer to `Date` for choosing an encoding. This is the default strategy.
        case deferredToDate

        /// Encode the `Date` as a UNIX timestamp (as a YAML number).
        case secondsSince1970

        /// Encode the `Date` as UNIX millisecond timestamp (as a YAML number).
        case millisecondsSince1970

        /// Encode the `Date` as an ISO-8601-formatted string (in RFC 3339 format).
        @available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
        case iso8601

        /// Encode the `Date` as a string formatted by the given formatter.
        case formatted(DateFormatter)

        /// Encode the `Date` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Date, Encoder) throws -> Void)
    }

    /// The strategy to use for encoding `Data` values.
    public enum DataEncodingStrategy {
        /// Defer to `Data` for choosing an encoding.
        case deferredToData

        /// Encoded the `Data` as a Base64-encoded string. This is the default strategy.
        case base64

        /// Encode the `Data` as a custom value encoded by the given closure.
        ///
        /// If the closure fails to encode a value into the given encoder, the encoder will encode an empty automatic container in its place.
        case custom((Data, Encoder) throws -> Void)
    }

    /// The strategy to use for non-YAML-conforming floating-point values (IEEE 754 infinity and NaN).
    public enum NonConformingFloatEncodingStrategy {
        /// Throw upon encountering non-conforming values. This is the default strategy.
        case `throw`

        /// Encode the values using the given representation strings.
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// The strategy to use for automatically changing the value of keys before encoding.
    public enum KeyEncodingStrategy {
        /// Use the keys specified by each type. This is the default strategy.
        case useDefaultKeys

        /// convert keyname to camel case.
        /// for example myMaxValue becomes MyMaxValue
        case camelCase

        fileprivate static func _convertToCamelCase(_ stringKey: String) -> String {
            stringKey.prefix(1).capitalized + stringKey.dropFirst()
        }
    }

    /// The output format to produce. Defaults to `withoutEscapingSlashes` for YAML.
    open var outputFormatting: OutputFormatting = [OutputFormatting.withoutEscapingSlashes]

    /// The strategy to use in encoding dates. Defaults to `.deferredToDate`.
    open var dateEncodingStrategy: DateEncodingStrategy = .deferredToDate

    /// The strategy to use in encoding binary data. Defaults to `.base64`.
    open var dataEncodingStrategy: DataEncodingStrategy = .base64

    /// The strategy to use in encoding non-conforming numbers. Defaults to `.throw`.
    open var nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy = .throw

    /// The strategy to use for encoding keys. Defaults to `.useDefaultKeys`.
    open var keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys

    /// Contextual user-provided information for use during encoding.
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    /// the number of space characters  for a single indent
    public static let singleIndent: Int = 3

    /// Options set on the top-level encoder to pass down the encoding hierarchy.
    fileprivate struct _Options {
        let dateEncodingStrategy: DateEncodingStrategy
        let dataEncodingStrategy: DataEncodingStrategy
        let nonConformingFloatEncodingStrategy: NonConformingFloatEncodingStrategy
        let keyEncodingStrategy: KeyEncodingStrategy
        let userInfo: [CodingUserInfoKey: Any]
    }

    /// The options set on the top-level encoder.
    fileprivate var options: _Options {
        _Options(
            dateEncodingStrategy: self.dateEncodingStrategy,
            dataEncodingStrategy: self.dataEncodingStrategy,
            nonConformingFloatEncodingStrategy: self.nonConformingFloatEncodingStrategy,
            keyEncodingStrategy: self.keyEncodingStrategy,
            userInfo: self.userInfo
        )
    }

    // MARK: - Constructing a YAML Encoder

    /// Initializes `self` with default strategies.
    public init() {}

    // MARK: - Encoding Values

    /// Encodes the given top-level value and returns its YAML representation.
    ///
    /// - parameter value: The value to encode.
    /// - returns: A new `Data` value containing the encoded YAML data.
    /// - throws: `EncodingError.invalidValue` if a non-conforming floating-point value is encountered during encoding, and the encoding strategy is `.throw`.
    /// - throws: An error if any value throws an error during encoding.
    open func encode<T: Encodable>(_ value: T) throws -> Data {
        let value: YAMLValue = try encodeAsYAMLValue(value)
        let writer = YAMLValue.Writer(options: self.outputFormatting)
        let bytes = writer.writeValue(value)

        return Data(bytes)
    }

    func encodeAsYAMLValue<T: Encodable>(_ value: T) throws -> YAMLValue {
        let encoder = YAMLEncoderImpl(options: self.options, codingPath: [])
        guard let topLevel = try encoder.wrapEncodable(value, for: nil) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [], debugDescription: "Top-level \(T.self) did not encode any values."
                )
            )
        }

        return topLevel
    }
}

// MARK: - _YAMLEncoder

private enum YAMLFuture {
    case value(YAMLValue)
    case encoder(YAMLEncoderImpl)
    case nestedArray(RefArray)
    case nestedObject(RefObject)

    class RefArray {
        private(set) var array: [YAMLFuture] = []

        init() {
            self.array.reserveCapacity(10)
        }

        @inline(__always) func append(_ element: YAMLValue) {
            self.array.append(.value(element))
        }

        @inline(__always) func append(_ encoder: YAMLEncoderImpl) {
            self.array.append(.encoder(encoder))
        }

        @inline(__always) func appendArray() -> RefArray {
            let array = RefArray()
            self.array.append(.nestedArray(array))
            return array
        }

        @inline(__always) func appendObject() -> RefObject {
            let object = RefObject()
            self.array.append(.nestedObject(object))
            return object
        }

        var values: [YAMLValue] {
            self.array.map { future -> YAMLValue in
                switch future {
                case .value(let value):
                    return value
                case .nestedArray(let array):
                    return .array(array.values)
                case .nestedObject(let object):
                    return .object(object.values)
                case .encoder(let encoder):
                    return encoder.value ?? .object([:])
                }
            }
        }
    }

    class RefObject {
        private(set) var dict: [String: YAMLFuture] = [:]

        init() {
            self.dict.reserveCapacity(20)
        }

        @inline(__always) func set(_ value: YAMLValue, for key: String) {
            self.dict[key] = .value(value)
        }

        @inline(__always) func setArray(for key: String) -> RefArray {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .nestedArray(let array):
                return array
            case .none, .value:
                let array = RefArray()
                self.dict[key] = .nestedArray(array)
                return array
            }
        }

        @inline(__always) func setObject(for key: String) -> RefObject {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject(let object):
                return object
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .none, .value:
                let object = RefObject()
                self.dict[key] = .nestedObject(object)
                return object
            }
        }

        @inline(__always) func set(_ encoder: YAMLEncoderImpl, for key: String) {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .none, .value:
                self.dict[key] = .encoder(encoder)
            }
        }

        var values: [String: YAMLValue] {
            self.dict.mapValues { future -> YAMLValue in
                switch future {
                case .value(let value):
                    return value
                case .nestedArray(let array):
                    return .array(array.values)
                case .nestedObject(let object):
                    return .object(object.values)
                case .encoder(let encoder):
                    return encoder.value ?? .object([:])
                }
            }
        }
    }
}

private class YAMLEncoderImpl {
    let options: YAMLEncoder._Options
    let codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] {
        self.options.userInfo
    }

    var singleValue: YAMLValue?
    var array: YAMLFuture.RefArray?
    var object: YAMLFuture.RefObject?

    var value: YAMLValue? {
        if let object = self.object {
            return .object(object.values)
        }
        if let array = self.array {
            return .array(array.values)
        }
        return self.singleValue
    }

    init(options: YAMLEncoder._Options, codingPath: [CodingKey]) {
        self.options = options
        self.codingPath = codingPath
    }
}

extension YAMLEncoderImpl: Encoder {
    func container<Key>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        if let _ = object {
            let container = YAMLKeyedEncodingContainer<Key>(impl: self, codingPath: codingPath)
            return KeyedEncodingContainer(container)
        }

        guard self.singleValue == nil, self.array == nil else {
            preconditionFailure()
        }

        self.object = YAMLFuture.RefObject()
        let container = YAMLKeyedEncodingContainer<Key>(impl: self, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        if let _ = array {
            return YAMLUnkeyedEncodingContainer(impl: self, codingPath: self.codingPath)
        }

        guard self.singleValue == nil, self.object == nil else {
            preconditionFailure()
        }

        self.array = YAMLFuture.RefArray()
        return YAMLUnkeyedEncodingContainer(impl: self, codingPath: self.codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        guard self.object == nil, self.array == nil else {
            preconditionFailure()
        }

        return YAMLSingleValueEncodingContainer(impl: self, codingPath: self.codingPath)
    }
}

// this is a private protocol to implement convenience methods directly on the EncodingContainers

extension YAMLEncoderImpl: _SpecialTreatmentEncoder {
    var impl: YAMLEncoderImpl {
        self
    }

    // untyped escape hatch. needed for `wrapObject`
    func wrapUntyped(_ encodable: Encodable) throws -> YAMLValue {
        switch encodable {
        case let date as Date:
            return try self.wrapDate(date, for: nil)
        case let data as Data:
            return try self.wrapData(data, for: nil)
        case let url as URL:
            return .string(url.absoluteString)
        case let decimal as Decimal:
            return .number(decimal.description)
        case let object as [String: Encodable]: // this emits a warning, but it works perfectly
            return try self.wrapObject(object, for: nil)
        default:
            try encodable.encode(to: self)
            return self.value ?? .object([:])
        }
    }
}

private protocol _SpecialTreatmentEncoder {
    var codingPath: [CodingKey] { get }
    var options: YAMLEncoder._Options { get }
    var impl: YAMLEncoderImpl { get }
}

extension _SpecialTreatmentEncoder {
    @inline(__always) fileprivate func wrapFloat<F: FloatingPoint & CustomStringConvertible>(
        _ float: F, for additionalKey: CodingKey?
    ) throws -> YAMLValue {
        guard !float.isNaN, !float.isInfinite else {
            if case .convertToString(let posInfString, let negInfString, let nanString) = self.options
                .nonConformingFloatEncodingStrategy {
                switch float {
                case F.infinity:
                    return .string(posInfString)
                case -F.infinity:
                    return .string(negInfString)
                default:
                    // must be nan in this case
                    return .string(nanString)
                }
            }

            var path = self.codingPath
            if let additionalKey = additionalKey {
                path.append(additionalKey)
            }

            throw EncodingError.invalidValue(
                float,
                .init(
                    codingPath: path,
                    debugDescription: "Unable to encode \(F.self).\(float) directly in YAML."
                )
            )
        }

        var string = float.description
        if string.hasSuffix(".0") {
            string.removeLast(2)
        }
        return .number(string)
    }

    fileprivate func wrapEncodable<E: Encodable>(_ encodable: E, for additionalKey: CodingKey?) throws
        -> YAMLValue? {
        switch encodable {
        case let date as Date:
            return try self.wrapDate(date, for: additionalKey)
        case let data as Data:
            return try self.wrapData(data, for: additionalKey)
        case let url as URL:
            return .string(url.absoluteString)
        case let decimal as Decimal:
            return .number(decimal.description)
        case let object as _YAMLStringDictionaryEncodableMarker:
            return try self.wrapObject(object as! [String: Encodable], for: additionalKey)
        default:
            let encoder = self.getEncoder(for: additionalKey)
            try encodable.encode(to: encoder)
            return encoder.value
        }
    }

    func wrapDate(_ date: Date, for additionalKey: CodingKey?) throws -> YAMLValue {
        switch self.options.dateEncodingStrategy {
        case .deferredToDate:
            let encoder = self.getEncoder(for: additionalKey)
            try date.encode(to: encoder)
            return encoder.value ?? .null

        case .secondsSince1970:
            return .number(date.timeIntervalSince1970.description)

        case .millisecondsSince1970:
            return .number((date.timeIntervalSince1970 * 1000).description)

        case .iso8601:
            if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                return .string(_iso8601Formatter.string(from: date))
            } else {
                fatalError("ISO8601DateFormatter is unavailable on this platform.")
            }

        case .formatted(let formatter):
            return .string(formatter.string(from: date))

        case .custom(let closure):
            let encoder = self.getEncoder(for: additionalKey)
            try closure(date, encoder)
            // The closure didn't encode anything. Return the default keyed container.
            return encoder.value ?? .object([:])
        }
    }

    func wrapData(_ data: Data, for additionalKey: CodingKey?) throws -> YAMLValue {
        switch self.options.dataEncodingStrategy {
        case .deferredToData:
            let encoder = self.getEncoder(for: additionalKey)
            try data.encode(to: encoder)
            return encoder.value ?? .null

        case .base64:
            let base64 = data.base64EncodedString()
            return .string(base64)

        case .custom(let closure):
            let encoder = self.getEncoder(for: additionalKey)
            try closure(data, encoder)
            // The closure didn't encode anything. Return the default keyed container.
            return encoder.value ?? .object([:])
        }
    }

    func wrapObject(_ object: [String: Encodable], for additionalKey: CodingKey?) throws -> YAMLValue {
        var baseCodingPath = self.codingPath
        if let additionalKey = additionalKey {
            baseCodingPath.append(additionalKey)
        }
        var result = [String: YAMLValue]()
        result.reserveCapacity(object.count)

        try object.forEach { key, value in
            var elemCodingPath = baseCodingPath
            elemCodingPath.append(_YAMLKey(stringValue: key))

            let encoder = YAMLEncoderImpl(options: self.options, codingPath: elemCodingPath)

            var convertedKey = key
            if self.options.keyEncodingStrategy == .camelCase {
                convertedKey = YAMLEncoder.KeyEncodingStrategy._convertToCamelCase(key)
            }
            result[convertedKey] = try encoder.wrapUntyped(value)
        }

        return .object(result)
    }

    fileprivate func getEncoder(for additionalKey: CodingKey?) -> YAMLEncoderImpl {
        if let additionalKey = additionalKey {
            var newCodingPath = self.codingPath
            newCodingPath.append(additionalKey)
            return YAMLEncoderImpl(options: self.options, codingPath: newCodingPath)
        }

        return self.impl
    }
}

private struct YAMLKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol,
    _SpecialTreatmentEncoder {
    typealias Key = K

    let impl: YAMLEncoderImpl
    let object: YAMLFuture.RefObject
    let codingPath: [CodingKey]

    private var firstValueWritten: Bool = false
    fileprivate var options: YAMLEncoder._Options {
        self.impl.options
    }

    init(impl: YAMLEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.object = impl.object!
        self.codingPath = codingPath
    }

    // used for nested containers
    init(impl: YAMLEncoderImpl, object: YAMLFuture.RefObject, codingPath: [CodingKey]) {
        self.impl = impl
        self.object = object
        self.codingPath = codingPath
    }

    private func _converted(_ key: Key) -> CodingKey {
        switch self.options.keyEncodingStrategy {
        case .useDefaultKeys:
            return key
        case .camelCase:
            let newKeyString = YAMLEncoder.KeyEncodingStrategy._convertToCamelCase(key.stringValue)
            return _YAMLKey(stringValue: newKeyString, intValue: key.intValue)
        }
    }

    mutating func encodeNil(forKey key: Self.Key) throws {
        self.object.set(.null, for: self._converted(key).stringValue)
    }

    mutating func encode(_ value: Bool, forKey key: Self.Key) throws {
        self.object.set(.bool(value), for: self._converted(key).stringValue)
    }

    mutating func encode(_ value: String, forKey key: Self.Key) throws {
        self.object.set(.string(value), for: self._converted(key).stringValue)
    }

    mutating func encode(_ value: Double, forKey key: Self.Key) throws {
        try encodeFloatingPoint(value, key: self._converted(key))
    }

    mutating func encode(_ value: Float, forKey key: Self.Key) throws {
        try encodeFloatingPoint(value, key: self._converted(key))
    }

    mutating func encode(_ value: Int, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: Int8, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: Int16, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: Int32, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: Int64, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: UInt, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: UInt8, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: UInt16, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: UInt32, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode(_ value: UInt64, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: self._converted(key))
    }

    mutating func encode<T>(_ value: T, forKey key: Self.Key) throws where T: Encodable {
        let convertedKey = self._converted(key)
        let encoded = try self.wrapEncodable(value, for: convertedKey)
        self.object.set(encoded ?? .object([:]), for: convertedKey.stringValue)
    }

    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type, forKey key: Self.Key)
        -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let convertedKey = self._converted(key)
        let newPath = self.codingPath + [convertedKey]
        let object = self.object.setObject(for: convertedKey.stringValue)
        let nestedContainer = YAMLKeyedEncodingContainer<NestedKey>(
            impl: impl, object: object, codingPath: newPath
        )
        return KeyedEncodingContainer(nestedContainer)
    }

    mutating func nestedUnkeyedContainer(forKey key: Self.Key) -> UnkeyedEncodingContainer {
        let convertedKey = self._converted(key)
        let newPath = self.codingPath + [convertedKey]
        let array = self.object.setArray(for: convertedKey.stringValue)
        let nestedContainer = YAMLUnkeyedEncodingContainer(
            impl: impl, array: array, codingPath: newPath
        )
        return nestedContainer
    }

    mutating func superEncoder() -> Encoder {
        let newEncoder = self.getEncoder(for: _YAMLKey.super)
        self.object.set(newEncoder, for: _YAMLKey.super.stringValue)
        return newEncoder
    }

    mutating func superEncoder(forKey key: Self.Key) -> Encoder {
        let convertedKey = self._converted(key)
        let newEncoder = self.getEncoder(for: convertedKey)
        self.object.set(newEncoder, for: convertedKey.stringValue)
        return newEncoder
    }
}

extension YAMLKeyedEncodingContainer {
    @inline(__always)
    private mutating func encodeFloatingPoint<F: FloatingPoint & CustomStringConvertible>(
        _ float: F, key: CodingKey
    ) throws {
        let value = try self.wrapFloat(float, for: key)
        self.object.set(value, for: key.stringValue)
    }

    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(
        _ value: N, key: CodingKey
    ) throws {
        self.object.set(.number(value.description), for: key.stringValue)
    }
}

private struct YAMLUnkeyedEncodingContainer: UnkeyedEncodingContainer, _SpecialTreatmentEncoder {
    let impl: YAMLEncoderImpl
    let array: YAMLFuture.RefArray
    let codingPath: [CodingKey]

    var count: Int {
        self.array.array.count
    }

    private var firstValueWritten: Bool = false
    fileprivate var options: YAMLEncoder._Options {
        self.impl.options
    }

    init(impl: YAMLEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.array = impl.array!
        self.codingPath = codingPath
    }

    // used for nested containers
    init(impl: YAMLEncoderImpl, array: YAMLFuture.RefArray, codingPath: [CodingKey]) {
        self.impl = impl
        self.array = array
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws {
        self.array.append(.null)
    }

    mutating func encode(_ value: Bool) throws {
        self.array.append(.bool(value))
    }

    mutating func encode(_ value: String) throws {
        self.array.append(.string(value))
    }

    mutating func encode(_ value: Double) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: Float) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: Int) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int64) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt64) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode<T>(_ value: T) throws where T: Encodable {
        let key = _YAMLKey(stringValue: "Index \(self.count)", intValue: self.count)
        let encoded = try self.wrapEncodable(value, for: key)
        self.array.append(encoded ?? .object([:]))
    }

    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) -> KeyedEncodingContainer<
        NestedKey
    > where NestedKey: CodingKey {
        let newPath = self.codingPath + [_YAMLKey(index: self.count)]
        let object = self.array.appendObject()
        let nestedContainer = YAMLKeyedEncodingContainer<NestedKey>(
            impl: impl, object: object, codingPath: newPath
        )
        return KeyedEncodingContainer(nestedContainer)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let newPath = self.codingPath + [_YAMLKey(index: self.count)]
        let array = self.array.appendArray()
        let nestedContainer = YAMLUnkeyedEncodingContainer(
            impl: impl, array: array, codingPath: newPath
        )
        return nestedContainer
    }

    mutating func superEncoder() -> Encoder {
        let encoder = self.getEncoder(for: _YAMLKey(index: self.count))
        self.array.append(encoder)
        return encoder
    }
}

extension YAMLUnkeyedEncodingContainer {
    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(_ value: N)
        throws {
        self.array.append(.number(value.description))
    }

    @inline(__always)
    private mutating func encodeFloatingPoint<F: FloatingPoint & CustomStringConvertible>(_ float: F)
        throws {
        let value = try self.wrapFloat(float, for: _YAMLKey(index: self.count))
        self.array.append(value)
    }
}

private struct YAMLSingleValueEncodingContainer: SingleValueEncodingContainer,
    _SpecialTreatmentEncoder {
    let impl: YAMLEncoderImpl
    let codingPath: [CodingKey]

    private var firstValueWritten: Bool = false
    fileprivate var options: YAMLEncoder._Options {
        self.impl.options
    }

    init(impl: YAMLEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .null
    }

    mutating func encode(_ value: Bool) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .bool(value)
    }

    mutating func encode(_ value: Int) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int64) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt64) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Float) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: Double) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: String) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .string(value)
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = try self.wrapEncodable(value, for: nil)
    }

    func preconditionCanEncodeNewValue() {
        precondition(
            self.impl.singleValue == nil,
            "Attempt to encode value through single value container when previously value already encoded."
        )
    }
}

extension YAMLSingleValueEncodingContainer {
    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(_ value: N)
        throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .number(value.description)
    }

    @inline(__always)
    private mutating func encodeFloatingPoint<F: FloatingPoint & CustomStringConvertible>(_ float: F)
        throws {
        self.preconditionCanEncodeNewValue()
        let value = try self.wrapFloat(float, for: nil)
        self.impl.singleValue = value
    }
}

extension YAMLValue {
    fileprivate struct Writer {
        let options: YAMLEncoder.OutputFormatting

        init(options: YAMLEncoder.OutputFormatting) {
            self.options = options
        }

        func writeValue(_ value: YAMLValue) -> [UInt8] {
            var bytes = [UInt8]()
            self.writeValuePretty(value, into: &bytes)
            return bytes
        }

        private func addInset(to bytes: inout [UInt8], depth: Int) {
            bytes.append(contentsOf: [UInt8](repeating: ._space, count: depth * YAMLEncoder.singleIndent))
        }

        private func writeValuePretty(_ value: YAMLValue, into bytes: inout [UInt8], depth: Int = 0) {
            switch value {
            case .null:
                if bytes.count > 0 { bytes.append(contentsOf: [._space]) }
                bytes.append(contentsOf: [UInt8]._null)
            case .bool(true):
                if bytes.count > 0 { bytes.append(contentsOf: [._space]) }
                bytes.append(contentsOf: [UInt8]._true)
            case .bool(false):
                if bytes.count > 0 { bytes.append(contentsOf: [._space]) }
                bytes.append(contentsOf: [UInt8]._false)
            case .string(let string):
                if bytes.count > 0 { bytes.append(contentsOf: [._space]) }
                self.encodeString(string, to: &bytes)
            case .number(let string):
                if bytes.count > 0 { bytes.append(contentsOf: [._space]) }
                bytes.append(contentsOf: string.utf8)
            case .array(let array):
                var iterator = array.makeIterator()
                while let item = iterator.next() {
                    bytes.append(contentsOf: [._newline])
                    self.addInset(to: &bytes, depth: depth)
                    bytes.append(contentsOf: [._dash])
                    self.writeValuePretty(item, into: &bytes, depth: depth + 1)
                }
            case .object(let dict):
                if self.options.contains(.sortedKeys) {
                    let sorted = dict.sorted { $0.key < $1.key }
                    self.writePrettyObject(sorted, into: &bytes)
                } else {
                    self.writePrettyObject(dict, into: &bytes, depth: depth)
                }
            }
        }

        private func writePrettyObject<Object: Sequence>(
            _ object: Object, into bytes: inout [UInt8], depth: Int = 0
        )
            where Object.Element == (key: String, value: YAMLValue) {
            var iterator = object.makeIterator()

            while let (key, value) = iterator.next() {
                // add a new line when other objects are present already
                if bytes.count > 0 {
                    bytes.append(contentsOf: [._newline])
                }
                self.addInset(to: &bytes, depth: depth)
                // key
                self.encodeString(key, to: &bytes)
                bytes.append(contentsOf: [._colon])
                // value
                self.writeValuePretty(value, into: &bytes, depth: depth + 1)
            }
            //            self.addInset(to: &bytes, depth: depth)
        }

        private func encodeString(_ string: String, to bytes: inout [UInt8]) {
            let stringBytes = string.utf8
            var startCopyIndex = stringBytes.startIndex
            var nextIndex = startCopyIndex

            while nextIndex != stringBytes.endIndex {
                switch stringBytes[nextIndex] {
                case 0 ..< 32, UInt8(ascii: "\""), UInt8(ascii: "\\"):
                    // All Unicode characters may be placed within the
                    // quotation marks, except for the characters that MUST be escaped:
                    // quotation mark, reverse solidus, and the control characters (U+0000
                    // through U+001F).
                    // https://tools.ietf.org/html/rfc8259#section-7

                    // copy the current range over
                    bytes.append(contentsOf: stringBytes[startCopyIndex ..< nextIndex])
                    switch stringBytes[nextIndex] {
                    case UInt8(ascii: "\""): // quotation mark
                        bytes.append(contentsOf: [._backslash, ._quote])
                    case UInt8(ascii: "\\"): // reverse solidus
                        bytes.append(contentsOf: [._backslash, ._backslash])
                    case 0x08: // backspace
                        bytes.append(contentsOf: [._backslash, UInt8(ascii: "b")])
                    case 0x0C: // form feed
                        bytes.append(contentsOf: [._backslash, UInt8(ascii: "f")])
                    case 0x0A: // line feed
                        bytes.append(contentsOf: [._backslash, UInt8(ascii: "n")])
                    case 0x0D: // carriage return
                        bytes.append(contentsOf: [._backslash, UInt8(ascii: "r")])
                    case 0x09: // tab
                        bytes.append(contentsOf: [._backslash, UInt8(ascii: "t")])
                    default:
                        func valueToAscii(_ value: UInt8) -> UInt8 {
                            switch value {
                            case 0 ... 9:
                                return value + UInt8(ascii: "0")
                            case 10 ... 15:
                                return value - 10 + UInt8(ascii: "a")
                            default:
                                preconditionFailure()
                            }
                        }
                        bytes.append(UInt8(ascii: "\\"))
                        bytes.append(UInt8(ascii: "u"))
                        bytes.append(UInt8(ascii: "0"))
                        bytes.append(UInt8(ascii: "0"))
                        let first = stringBytes[nextIndex] / 16
                        let remaining = stringBytes[nextIndex] % 16
                        bytes.append(valueToAscii(first))
                        bytes.append(valueToAscii(remaining))
                    }

                    nextIndex = stringBytes.index(after: nextIndex)
                    startCopyIndex = nextIndex
                case UInt8(ascii: "/") where self.options.contains(.withoutEscapingSlashes) == false:
                    bytes.append(contentsOf: stringBytes[startCopyIndex ..< nextIndex])
                    bytes.append(contentsOf: [._backslash, UInt8(ascii: "/")])
                    nextIndex = stringBytes.index(after: nextIndex)
                    startCopyIndex = nextIndex
                default:
                    nextIndex = stringBytes.index(after: nextIndex)
                }
            }

            // copy everything, that hasn't been copied yet
            bytes.append(contentsOf: stringBytes[startCopyIndex ..< nextIndex])
        }
    }
}

// ===----------------------------------------------------------------------===//
// Shared Key Types
// ===----------------------------------------------------------------------===//

struct _YAMLKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    public init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    public init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }

    static let `super` = _YAMLKey(stringValue: "super")
}

// ===----------------------------------------------------------------------===//
// Shared ISO8601 Date Formatter
// ===----------------------------------------------------------------------===//

// NOTE: This value is implicitly lazy and _must_ be lazy. We're compiled against the latest SDK (w/ ISO8601DateFormatter), but linked against whichever Foundation the user has. ISO8601DateFormatter might not exist, so we better not hit this code path on an older OS.
@available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
var _iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = .withInternetDateTime
    return formatter
}()

// ===----------------------------------------------------------------------===//
// Error Utilities
// ===----------------------------------------------------------------------===//

extension EncodingError {
    /// Returns a `.invalidValue` error describing the given invalid floating-point value.
    ///
    ///
    /// - parameter value: The value that was invalid to encode.
    /// - parameter path: The path of `CodingKey`s taken to encode this value.
    /// - returns: An `EncodingError` with the appropriate path and debug description.
    fileprivate static func _invalidFloatingPointValue<T: FloatingPoint>(
        _ value: T, at codingPath: [CodingKey]
    ) -> EncodingError {
        let valueDescription: String
        if value == T.infinity {
            valueDescription = "\(T.self).infinity"
        } else if value == -T.infinity {
            valueDescription = "-\(T.self).infinity"
        } else {
            valueDescription = "\(T.self).nan"
        }

        let debugDescription =
            "Unable to encode \(valueDescription) directly in YAML. Use YAMLEncoder.NonConformingFloatEncodingStrategy.convertToString to specify how the value should be encoded."
        return .invalidValue(
            value, EncodingError.Context(codingPath: codingPath, debugDescription: debugDescription)
        )
    }
}

enum YAMLValue: Equatable {
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    case array([YAMLValue])
    case object([String: YAMLValue])
}

extension YAMLValue {
    private var isValue: Bool {
        switch self {
        case .array, .object:
            return false
        case .null, .number, .string, .bool:
            return true
        }
    }

    private var isContainer: Bool {
        switch self {
        case .array, .object:
            return true
        case .null, .number, .string, .bool:
            return false
        }
    }
}

extension YAMLValue {
    private var debugDataTypeDescription: String {
        switch self {
        case .array:
            return "an array"
        case .bool:
            return "bool"
        case .number:
            return "a number"
        case .string:
            return "a string"
        case .object:
            return "a dictionary"
        case .null:
            return "null"
        }
    }
}

extension UInt8 {
    static let _space = UInt8(ascii: " ")
    static let _return = UInt8(ascii: "\r")
    static let _newline = UInt8(ascii: "\n")
    static let _tab = UInt8(ascii: "\t")

    static let _colon = UInt8(ascii: ":")
    static let _comma = UInt8(ascii: ",")

    static let _openbrace = UInt8(ascii: "{")
    static let _closebrace = UInt8(ascii: "}")

    static let _openbracket = UInt8(ascii: "[")
    static let _closebracket = UInt8(ascii: "]")

    static let _quote = UInt8(ascii: "\"")
    static let _backslash = UInt8(ascii: "\\")

    static let _dash = UInt8(ascii: "-")
}

extension Array where Element == UInt8 {
    static let _true = [
        UInt8(ascii: "t"), UInt8(ascii: "r"), UInt8(ascii: "u"), UInt8(ascii: "e"),
    ]
    static let _false = [
        UInt8(ascii: "f"), UInt8(ascii: "a"), UInt8(ascii: "l"), UInt8(ascii: "s"), UInt8(ascii: "e"),
    ]
    static let _null = [
        UInt8(ascii: "n"), UInt8(ascii: "u"), UInt8(ascii: "l"), UInt8(ascii: "l"),
    ]
}
