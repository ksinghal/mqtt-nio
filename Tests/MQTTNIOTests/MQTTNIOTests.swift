import XCTest
import Foundation
import Logging
import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOSSL
@testable import MQTTNIO

final class MQTTNIOTests: XCTestCase {
    static let hostname = ProcessInfo.processInfo.environment["MOSQUITTO_SERVER"] ?? "localhost"
    
    func connect(to client: MQTTClient) throws {
        try client.connect().wait()
    }

    func testConnectWithWill() throws {
        let client = createClient(identifier: "testConnectWithWill")
        try client.connect(
            will: (topicName: "MyWillTopic", payload: ByteBufferAllocator().buffer(string: "Test payload"), retain: false)
        ).wait()
        try client.ping().wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }
    
    func testWebsocketConnect() throws {
        let client = createWebSocketClient(identifier: "testWebsocketConnect")
        try client.connect().wait()
        try client.ping().wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testSSLConnect() throws {
        let client = try createSSLClient(identifier: "testSSLConnect")
        try client.connect().wait()
        try client.ping().wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testWebsocketAndSSLConnect() throws {
        let client = try createWebSocketAndSSLClient(identifier: "testWebsocketAndSSLConnect")
        try client.connect().wait()
        try client.ping().wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testMQTTPublishQoS0() throws {
        let client = self.createClient(identifier: "testMQTTPublishQoS0")
        try client.connect().wait()
        try client.publish(to: "testMQTTPublishQoS", payload: ByteBufferAllocator().buffer(string: "Test payload"), qos: .atMostOnce).wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testMQTTPublishQoS1() throws {
        let client = try self.createSSLClient(identifier: "testMQTTPublishQoS1")
        try client.connect().wait()
        try client.publish(to: "testMQTTPublishQoS", payload: ByteBufferAllocator().buffer(string: "Test payload"), qos: .atLeastOnce).wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testMQTTPublishQoS2() throws {
        let client = try self.createWebSocketAndSSLClient(identifier: "testMQTTPublishQoS2")
        try client.connect().wait()
        try client.publish(to: "testMQTTPublishQoS", payload: ByteBufferAllocator().buffer(string: "Test payload"), qos: .exactlyOnce).wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testMQTTPingreq() throws {
        let client = self.createClient(identifier: "testMQTTPingreq")
        try client.connect().wait()
        try client.ping().wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testMQTTSubscribe() throws {
        let client = self.createClient(identifier: "testMQTTSubscribe")
        try client.connect().wait()
        try client.subscribe(to: [.init(topicFilter: "iphone", qos: .atLeastOnce)]).wait()
        Thread.sleep(forTimeInterval: 5)
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testMQTTPublishToClient() throws {
        let lock = Lock()
        var publishReceived: [MQTTPublishInfo] = []
        let payloadString = #"{"from":1000000,"to":1234567,"type":1,"content":"I am a beginner in swift and I am studying hard!!测试\n\n test, message","timestamp":1607243024,"nonce":"pAx2EsUuXrVuiIU3GGOGHNbUjzRRdT5b","sign":"ff902e31a6a5f5343d70a3a93ac9f946adf1caccab539c6f3a6"}"#
        let payload = ByteBufferAllocator().buffer(string: payloadString)

        let client = self.createWebSocketClient(identifier: "testMQTTPublishToClient_publisher")
        try client.connect().wait()
        let client2 = self.createWebSocketClient(identifier: "testMQTTPublishToClient_subscriber")
        client2.addPublishListener(named: "test") { result in
            switch result {
            case .success(let publish):
                var buffer = publish.payload
                let string = buffer.readString(length: buffer.readableBytes)
                XCTAssertEqual(string, payloadString)
                lock.withLock {
                    publishReceived.append(publish)
                }
            case .failure(let error):
                XCTFail("\(error)")
            }
        }
        try client2.connect().wait()
        try client2.subscribe(to: [.init(topicFilter: "testMQTTAtLeastOnce", qos: .atLeastOnce)]).wait()
        try client2.subscribe(to: [.init(topicFilter: "testMQTTExactlyOnce", qos: .exactlyOnce)]).wait()
        try client.publish(to: "testMQTTAtLeastOnce", payload: payload, qos: .atLeastOnce).wait()
        try client.publish(to: "testMQTTExactlyOnce", payload: payload, qos: .exactlyOnce).wait()
        Thread.sleep(forTimeInterval: 2)
        lock.withLock {
            XCTAssertEqual(publishReceived.count, 2)
        }
        try client.disconnect().wait()
        try client2.disconnect().wait()
        try client.syncShutdownGracefully()
        try client2.syncShutdownGracefully()
    }

    func testMQTTPublishToClientLargePayload() throws {
        let lock = Lock()
        var publishReceived: [MQTTPublishInfo] = []
        let payloadSize = 65537
        let payloadData = Data(count: payloadSize)
        let payload = ByteBufferAllocator().buffer(data: payloadData)

        let client = self.createWebSocketClient(identifier: "testMQTTPublishToClientLargePayload_publisher")
        try client.connect().wait()
        let client2 = self.createWebSocketClient(identifier: "testMQTTPublishToClientLargePayload_subscriber")
        client2.addPublishListener(named: "test") { result in
            switch result {
            case .success(let publish):
                var buffer = publish.payload
                let data = buffer.readData(length: buffer.readableBytes)
                XCTAssertEqual(data, payloadData)
                lock.withLock {
                    publishReceived.append(publish)
                }
            case .failure(let error):
                XCTFail("\(error)")
            }
        }
        try client2.connect().wait()
        try client2.subscribe(to: [.init(topicFilter: "testMQTTAtLeastOnce", qos: .atLeastOnce)]).wait()
        try client.publish(to: "testMQTTAtLeastOnce", payload: payload, qos: .atLeastOnce).wait()
        Thread.sleep(forTimeInterval: 2)
        lock.withLock {
            XCTAssertEqual(publishReceived.count, 1)
        }
        try client.disconnect().wait()
        try client2.disconnect().wait()
        try client.syncShutdownGracefully()
        try client2.syncShutdownGracefully()
    }

    func testCloseListener() throws {
        let disconnected = NIOAtomic<Bool>.makeAtomic(value: false)
        let client = self.createWebSocketClient(identifier: "testCloseListener")
        let client2 = self.createWebSocketClient(identifier: "testCloseListener")

        client.addCloseListener(named: "Reconnect") { result in
            switch result {
            case .failure(let error):
                XCTFail("\(error)")
            case .success:
                disconnected.store(true)
            }
        }

        try client.connect().wait()
        // by connecting with same identifier the first client uses the first client is forced to disconnect
        try client2.connect().wait()

        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(disconnected.load())
        
        try client2.disconnect().wait()
        try client.syncShutdownGracefully()
        try client2.syncShutdownGracefully()
    }

    func testMQTTPublishQoS2WithStall() throws {
        let stallHandler = OutboundStallHandler { message in
            if message.type == .PUBLISH || message.type == .PUBREL {
                return .seconds(6)
            }
            return nil
        }
        let client = self.createClient(identifier: "testMQTTPublishQoS2WithStall", timeout: .seconds(4))
        try client.connect().wait()
        try client.connection?.channel.pipeline.addHandler(stallHandler).wait()
        try client.publish(to: "testMQTTPublishQoS2WithStall", payload: ByteBufferAllocator().buffer(string: "Test payload"), qos: .exactlyOnce).wait()
        try client.disconnect().wait()
        try client.syncShutdownGracefully()
    }

    func testMQTTSubscribeQoS2WithStall() throws {
        let stallHandler = InboundStallHandler { packet in
            if packet.type == .PUBREL {
                return .seconds(15)
            }
            return nil
        }
        let lock = Lock()
        var publishReceived: [MQTTPublishInfo] = []
        let payload = ByteBufferAllocator().buffer(string: "This is the Test payload")

        let client = self.createClient(identifier: "testMQTTPublishToClient_publisher", timeout: .seconds(2))
        try client.connect().wait()
        let client2 = self.createClient(identifier: "testMQTTPublishToClient_subscriber", timeout: .seconds(10))
        client2.addPublishListener(named: "test") { result in
            switch result {
            case .success(let publish):
                var buffer = publish.payload
                let string = buffer.readString(length: buffer.readableBytes)
                XCTAssertEqual(string, "This is the Test payload")
                lock.withLock {
                    publishReceived.append(publish)
                }
                print("Received: \(string!)")
            case .failure(let error):
                XCTFail("\(error)")
            }
        }
        try client2.connect().wait()
        try client2.connection?.channel.pipeline.addHandler(stallHandler, position: .first).wait()
        try client2.subscribe(to: [.init(topicFilter: "testMQTTSubscribeQoS2WithStall", qos: .exactlyOnce)]).wait()
        try client.publish(to: "testMQTTSubscribeQoS2WithStall", payload: payload, qos: .exactlyOnce).wait()

        Thread.sleep(forTimeInterval: 20)
        lock.withLock {
            XCTAssertEqual(publishReceived.count, 1)
        }
        try client.disconnect().wait()
        try client2.disconnect().wait()
        try client.syncShutdownGracefully()
        try client2.syncShutdownGracefully()
    }


    // MARK: Helper variables and functions

    func createClient(identifier: String, timeout: TimeAmount? = .seconds(10)) -> MQTTClient {
        MQTTClient(
            host: Self.hostname,
            port: 1883,
            identifier: identifier,
            eventLoopGroupProvider: .createNew,
            logger: self.logger,
            configuration: .init(timeout: timeout)
        )
    }

    func createWebSocketClient(identifier: String) -> MQTTClient {
        MQTTClient(
            host: Self.hostname,
            port: 8080,
            identifier: identifier,
            eventLoopGroupProvider: .createNew,
            logger: self.logger,
            configuration: .init(useWebSockets: true, webSocketURLPath: "/mqtt")
        )
    }

    func createSSLClient(identifier: String) throws -> MQTTClient {
        return try MQTTClient(
            host: Self.hostname,
            port: 8883,
            identifier: identifier,
            eventLoopGroupProvider: .createNew,
            logger: self.logger,
            configuration: .init(useSSL: true, tlsConfiguration: Self.getTLSConfiguration(withClientKey: true), sniServerName: "soto.codes")
        )
    }

    func createWebSocketAndSSLClient(identifier: String) throws -> MQTTClient {
        return try MQTTClient(
            host: Self.hostname,
            port: 8081,
            identifier: identifier,
            eventLoopGroupProvider: .createNew,
            logger: self.logger,
            configuration: .init(timeout: .seconds(5), useSSL: true, useWebSockets: true, tlsConfiguration: Self.getTLSConfiguration(), sniServerName: "soto.codes", webSocketURLPath: "/mqtt")
        )
    }

    let logger: Logger = {
        var logger = Logger(label: "MQTTTests")
        logger.logLevel = .trace
        return logger
    }()

    static var rootPath: String = {
        return #file
            .split(separator: "/", omittingEmptySubsequences: false)
            .dropLast(3)
            .map { String(describing: $0) }
            .joined(separator: "/")
    }()

    static var _tlsConfiguration: Result<MQTTClient.TLSConfigurationType, Error> = {
        do {
            #if os(Linux)
            
            let rootCertificate = try NIOSSLCertificate.fromPEMFile(MQTTNIOTests.rootPath + "/mosquitto/certs/ca.crt")
            let certificate = try NIOSSLCertificate.fromPEMFile(MQTTNIOTests.rootPath + "/mosquitto/certs/client.crt")
            let privateKey = try NIOSSLPrivateKey(file: MQTTNIOTests.rootPath + "/mosquitto/certs/client.key", format: .pem)
            let tlsConfiguration = TLSConfiguration.forClient(
                trustRoots: .certificates(rootCertificate),
                certificateChain: certificate.map{ .certificate($0) },
                privateKey: .privateKey(privateKey)
            )
            return .success(.niossl(tlsConfiguration))
            
            #else
            
            let rootCertificate = try NIOSSLCertificate.fromPEMFile(MQTTNIOTests.rootPath + "/mosquitto/certs/ca.crt")
            let trustRootCertificates = try rootCertificate.compactMap { SecCertificateCreateWithData(nil, Data(try $0.toDERBytes()) as CFData)}
            let data = try Data(contentsOf: URL(fileURLWithPath: MQTTNIOTests.rootPath + "/mosquitto/certs/client.p12"))
            let options: [String: String] = [kSecImportExportPassphrase as String: "BoQOxr1HFWb5poBJ0Z9tY1xcB"]
            var rawItems: CFArray?
            let rt = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
            let items = rawItems! as! Array<Dictionary<String, Any>>
            let firstItem = items[0]
            let identity = firstItem[kSecImportItemIdentity as String] as! SecIdentity?
            let tlsConfiguration = TSTLSConfiguration(
                trustRoots: trustRootCertificates,
                clientIdentity: identity
            )
            return .success(.ts(tlsConfiguration))
            
            #endif
        } catch {
            return .failure(error)
        }
    }()
    
    static func getTLSConfiguration(withTrustRoots: Bool = true, withClientKey: Bool = true) throws -> MQTTClient.TLSConfigurationType {
        switch _tlsConfiguration {
        case .success(let config):
            switch config {
            case .niossl(let config):
                return .niossl(TLSConfiguration.forClient(
                    trustRoots: withTrustRoots == true ? (config.trustRoots ?? .default) : .default,
                    certificateChain: withClientKey ? config.certificateChain : [],
                    privateKey: withClientKey ? config.privateKey : nil
                ))
            #if !os(Linux)
            case .ts(let config):
                return .ts(TSTLSConfiguration(
                    trustRoots: withTrustRoots == true ? config.trustRoots : nil,
                    clientIdentity: withClientKey == true ? config.clientIdentity : nil
                ))
            #endif
            }
        case .failure(let error):
            throw error
        }
    }
}

class OutboundStallHandler: ChannelOutboundHandler {
    typealias OutboundIn = MQTTOutboundMessage
    typealias OutboundOut = MQTTOutboundMessage

    let callback: (MQTTOutboundMessage) -> TimeAmount?

    init(callback: @escaping (MQTTOutboundMessage) -> TimeAmount?) {
        self.callback = callback
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        if let stallTime = callback(message) {
            context.eventLoop.scheduleTask(in: stallTime) {
                context.write(data, promise: promise)
            }
        } else {
            context.write(data, promise: promise)
        }
    }

}

class InboundStallHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    let callback: (MQTTPacketInfo) -> TimeAmount?

    init(callback: @escaping (MQTTPacketInfo) -> TimeAmount?) {
        self.callback = callback
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var bb = unwrapInboundIn(data)
        do {
            let packet = try MQTTSerializer.readIncomingPacket(from: &bb)
            if let stallTime = callback(packet) {
                context.eventLoop.scheduleTask(in: stallTime) {
                    context.fireChannelRead(data)
                }
                return
            }
        } catch {
        }
        context.fireChannelRead(data)
    }
}
