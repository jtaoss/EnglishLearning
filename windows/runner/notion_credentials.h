#ifndef RUNNER_NOTION_CREDENTIALS_H_
#define RUNNER_NOTION_CREDENTIALS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

// Current-user Windows Credential Manager. No files, logs, or arbitrary keys.
class NotionCredentials {
 public:
  explicit NotionCredentials(flutter::BinaryMessenger* messenger);
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
