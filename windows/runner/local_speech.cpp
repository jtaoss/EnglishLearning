#include "local_speech.h"
#include <flutter/standard_method_codec.h>
#include <windows.h>

namespace {
std::string Utf8(const wchar_t* value) {
  const int n = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  if (n <= 1) return "";
  std::string text(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, text.data(), n, nullptr, nullptr);
  text.pop_back();
  return text;
}
const flutter::EncodableValue* Arg(const flutter::MethodCall<flutter::EncodableValue>& call, const char* key) {
  const auto* map = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
  if (!map) return nullptr;
  const auto found = map->find(flutter::EncodableValue(key));
  return found == map->end() ? nullptr : &found->second;
}
}

bool LocalSpeech::Prepare() {
  if (voice_) return true;
  Microsoft::WRL::ComPtr<ISpObjectTokenCategory> category;
  Microsoft::WRL::ComPtr<IEnumSpObjectTokens> tokens;
  if (FAILED(CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(category.GetAddressOf()))) ||
      FAILED(category->SetId(SPCAT_VOICES, FALSE)) ||
      FAILED(category->EnumTokens(L"Language=409", nullptr, tokens.GetAddressOf()))) return false;
  Microsoft::WRL::ComPtr<ISpObjectToken> token;
  while (tokens->Next(1, token.ReleaseAndGetAddressOf(), nullptr) == S_OK) {
    wchar_t* description = nullptr;
    if (FAILED(token->GetStringValue(nullptr, &description))) continue;
    const std::wstring label(description);
    CoTaskMemFree(description);
    // Do not select third-party or online voices through this local fallback.
    if (label.find(L"Microsoft ") != 0 || label.find(L"Desktop") == std::wstring::npos) continue;
    Microsoft::WRL::ComPtr<ISpVoice> candidate;
    if (FAILED(CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(candidate.GetAddressOf()))) || FAILED(candidate->SetVoice(token.Get()))) continue;
    candidate->SetRate(0);
    voice_ = candidate;
    name_ = Utf8(label.c_str());
    return true;
  }
  return false;
}

LocalSpeech::LocalSpeech(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "english_learning/local_speech", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    using V = flutter::EncodableValue;
    if (call.method_name() == "voice") {
      if (!Prepare()) { result->Success(); return; }
      result->Success(V(flutter::EncodableMap{{V("name"),V(name_)},{V("locale"),V("en-US")}}));
      return;
    }
    if (call.method_name() == "speak") {
      const auto* arg = Arg(call, "text");
      const auto* text = arg ? std::get_if<std::string>(arg) : nullptr;
      if (!text || text->empty() || text->size() > 160 || text->find_first_of("<>\r\n") != std::string::npos) {
        result->Error("invalid_text", "Invalid word"); return;
      }
      if (!Prepare()) { result->Error("voice_unavailable", "No installed Microsoft US English Desktop voice"); return; }
      const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(), static_cast<int>(text->size()), nullptr, 0);
      if (!n) { result->Error("invalid_text", "Invalid word"); return; }
      std::wstring word(n, L'\0');
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(), static_cast<int>(text->size()), word.data(), n);
      ++generation_;
      // Plain text only: a word is never interpreted as SSML/XML or a filename.
      const HRESULT hr = voice_->Speak(word.c_str(), SPF_ASYNC | SPF_PURGEBEFORESPEAK | SPF_IS_NOT_XML, nullptr);
      if (FAILED(hr)) { result->Error("speech_failed", "Local speech failed"); return; }
      result->Success(V(generation_)); return;
    }
    if (call.method_name() == "status" || call.method_name() == "stop") {
      const auto* arg = Arg(call, "id");
      const auto* id = arg ? std::get_if<int32_t>(arg) : nullptr;
      if (!id || *id != generation_ || !voice_) {
        result->Error("interrupted", "Speech attempt is no longer current"); return;
      }
      if (call.method_name() == "stop") {
        voice_->Speak(nullptr, SPF_PURGEBEFORESPEAK, nullptr);
        ++generation_; result->Success(); return;
      }
      SPVOICESTATUS status = {};
      if (FAILED(voice_->GetStatus(&status, nullptr)) || FAILED(status.hrLastResult)) {
        result->Error("speech_failed", "Local speech failed"); return;
      }
      result->Success(V(status.dwRunningState == SPRS_DONE)); return;
    }
    result->NotImplemented();
  });
}
LocalSpeech::~LocalSpeech() {
  if (voice_) voice_->Speak(nullptr, SPF_PURGEBEFORESPEAK, nullptr);
}
