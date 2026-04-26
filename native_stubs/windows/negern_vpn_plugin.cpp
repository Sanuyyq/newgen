#include "negern_vpn_plugin.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

namespace negern {

using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {
int GetInt(const EncodableMap& map, const std::string& key, int def = -1) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return def;
  if (std::holds_alternative<int32_t>(it->second))
    return std::get<int32_t>(it->second);
  if (std::holds_alternative<int64_t>(it->second))
    return static_cast<int>(std::get<int64_t>(it->second));
  return def;
}
}  // namespace

// static
void NegernVpnPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto method = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "negern/vpn",
      &flutter::StandardMethodCodec::GetInstance());
  auto events = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "negern/vpn/events",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<NegernVpnPlugin>(std::move(method),
                                                  std::move(events));
  registrar->AddPlugin(std::move(plugin));
}

NegernVpnPlugin::NegernVpnPlugin(
    std::unique_ptr<flutter::MethodChannel<EncodableValue>> method,
    std::unique_ptr<flutter::EventChannel<EncodableValue>> events)
    : method_(std::move(method)), events_(std::move(events)) {
  method_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleCall(call, std::move(result));
      });

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<EncodableValue>>(
      [this](const EncodableValue*,
             std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        sink_ = std::move(events);
        return nullptr;
      },
      [this](const EncodableValue*)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        sink_.reset();
        return nullptr;
      });
  events_->SetStreamHandler(std::move(handler));
}

NegernVpnPlugin::~NegernVpnPlugin() = default;

void NegernVpnPlugin::HandleCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& name = call.method_name();
  if (name == "prepare") {
    // На Windows подготовка — это обеспечение admin/wintun. В скелете — true.
    result->Success(EncodableValue(true));
  } else if (name == "start") {
    int engine = -1;
    if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
      engine = GetInt(*args, "engine", -1);
    }
    running_engine_ = engine;
    EmitStatus("connecting", engine, 0, 0);
    // TODO: LoadLibraryW(xray.dll / awg.dll); вызвать Go-экспорты.
    EmitStatus("connected", engine, 0, 0);
    result->Success();
  } else if (name == "stop") {
    EmitStatus("disconnecting", running_engine_, 0, 0);
    running_engine_ = -1;
    // TODO: Stop() из Go-библиотеки.
    EmitStatus("disconnected", -1, 0, 0);
    result->Success();
  } else if (name == "status") {
    EncodableMap map;
    map[EncodableValue("state")] =
        EncodableValue(running_engine_ < 0 ? "disconnected" : "connected");
    map[EncodableValue("engine")] =
        running_engine_ < 0 ? EncodableValue() : EncodableValue(running_engine_);
    map[EncodableValue("upload")] = EncodableValue(0);
    map[EncodableValue("download")] = EncodableValue(0);
    result->Success(EncodableValue(map));
  } else {
    result->NotImplemented();
  }
}

void NegernVpnPlugin::EmitStatus(const std::string& state, int engine,
                                 int up, int down) {
  if (!sink_) return;
  EncodableMap map;
  map[EncodableValue("state")] = EncodableValue(state);
  map[EncodableValue("engine")] =
      engine < 0 ? EncodableValue() : EncodableValue(engine);
  map[EncodableValue("upload")] = EncodableValue(up);
  map[EncodableValue("download")] = EncodableValue(down);
  sink_->Success(EncodableValue(map));
}

}  // namespace negern
