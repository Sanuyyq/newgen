#pragma once

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace negern {

// Заготовка Windows-плагина. MethodChannel `negern/vpn` + EventChannel
// `negern/vpn/events`. Реальные движки (xray.dll / awg.dll) подключаются
// в следующих итерациях через LoadLibraryW + C-API.
class NegernVpnPlugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  NegernVpnPlugin(
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method,
      std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events);
  ~NegernVpnPlugin();

 private:
  void HandleCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void EmitStatus(const std::string& state, int engine, int up, int down);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  int running_engine_ = -1;
};

}  // namespace negern
