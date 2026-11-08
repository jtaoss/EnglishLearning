#include "notion_credentials.h"

#include <windows.h>
#include <wincred.h>
#include <flutter/standard_method_codec.h>
#include <string>

NotionCredentials::NotionCredentials(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "english_learning/notion_credentials",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([](
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto* args = call.arguments()
        ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    if (!args) { result->Error("invalid_arguments", "Invalid request"); return; }
    std::wstring target = L"EnglishLearning.Notion.ReadOnly.v1";
    const auto purpose = args->find(flutter::EncodableValue("purpose"));
    if (purpose != args->end()) {
      const auto* value = std::get_if<std::string>(&purpose->second);
      if (!value || *value != "event_sandbox") {
        result->Error("invalid_purpose", "Invalid credential purpose"); return;
      }
      target = L"EnglishLearning.Notion.EventSandbox.v1";
    }
    const auto test = args->find(flutter::EncodableValue("test_namespace"));
    if (test != args->end()) {
#ifndef NDEBUG
      const auto* value = std::get_if<std::string>(&test->second);
      if (!value || value->empty() || value->size() > 64 ||
          value->find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_") != std::string::npos) {
        result->Error("invalid_namespace", "Invalid test namespace"); return;
      }
      target = L"EnglishLearning.Notion.Test." + std::wstring(value->begin(), value->end());
#else
      result->Error("unsupported", "Test namespace unavailable"); return;
#endif
    }
    if (call.method_name() == "read") {
      PCREDENTIALW credential = nullptr;
      if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
        if (GetLastError() == ERROR_NOT_FOUND) { result->Success(); }
        else { result->Error("secure_read_failed", "Secure storage unavailable"); }
        return;
      }
      std::string value;
      if (credential->CredentialBlobSize > 0) {
        value.assign(reinterpret_cast<char*>(credential->CredentialBlob), credential->CredentialBlobSize);
        SecureZeroMemory(credential->CredentialBlob, credential->CredentialBlobSize);
      }
      CredFree(credential);
      result->Success(flutter::EncodableValue(value));
      if (!value.empty()) SecureZeroMemory(value.data(), value.size());
      return;
    }
    if (call.method_name() == "write") {
      const auto found = args->find(flutter::EncodableValue("value"));
      const auto* value = found == args->end() ? nullptr : std::get_if<std::string>(&found->second);
      if (!value || value->empty() || value->size() > CRED_MAX_CREDENTIAL_BLOB_SIZE) {
        result->Error("invalid_value", "Invalid secure configuration"); return;
      }
      CREDENTIALW credential = {};
      credential.Type = CRED_TYPE_GENERIC;
      credential.TargetName = const_cast<wchar_t*>(target.c_str());
      credential.CredentialBlobSize = static_cast<DWORD>(value->size());
      credential.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(value->data()));
      credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
      credential.UserName = const_cast<wchar_t*>(L"EnglishLearning");
      if (!CredWriteW(&credential, 0)) { result->Error("secure_write_failed", "Secure storage unavailable"); return; }
      result->Success(); return;
    }
    if (call.method_name() == "delete") {
      if (!CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0) && GetLastError() != ERROR_NOT_FOUND) {
        result->Error("secure_delete_failed", "Secure storage unavailable"); return;
      }
      result->Success(); return;
    }
    result->NotImplemented();
  });
}
