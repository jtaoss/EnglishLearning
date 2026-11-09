#ifndef RUNNER_LOCAL_SPEECH_H_
#define RUNNER_LOCAL_SPEECH_H_
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <sapi.h>
#include <wrl/client.h>
#include <memory>
#include <string>

// Installed Microsoft SAPI voice only. No network, exports or voice downloads.
class LocalSpeech {
 public:
  explicit LocalSpeech(flutter::BinaryMessenger* messenger);
  ~LocalSpeech();
 private:
  bool Prepare();
  Microsoft::WRL::ComPtr<ISpVoice> voice_;
  std::string name_;
  int generation_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
