import Flutter
import UIKit

public class SwiftEspProvisioningBlePlugin: NSObject, FlutterPlugin {
  private var cryptoAES: CryptoAES?
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "esp_provisioning_ble", binaryMessenger: registrar.messenger())
    let instance = SwiftEspProvisioningBlePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "init":
        let args = call.arguments as! NSDictionary
        let key = args["key"] as! FlutterStandardTypedData
        let iv = args["iv"] as! FlutterStandardTypedData
        cryptoAES = CryptoAES(key: key.data, iv: iv.data)
        result(true)
    case "crypt":
        let args = call.arguments as! NSDictionary
        let data = args["data"] as! FlutterStandardTypedData
        guard let cryptoAES = self.cryptoAES else {
            return
        }
        let ret = cryptoAES.encrypt(data: data.data)

        result(FlutterStandardTypedData(bytes: ret!))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
