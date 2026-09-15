#ifndef ZECTRIX_SELF_TEST_H_
#define ZECTRIX_SELF_TEST_H_

#include <array>
#include <cstdint>
#include <functional>

class ZectrixBoard;

enum class ZectrixTestId : uint8_t {
    kRf = 0,
    kAudio,
    kRtc,
    kCharge,
    kLed,
    kButtons,
    kNfc,
    kCount,
};

enum class ZectrixTestState : uint8_t {
    kWait = 0,
    kRunning,
    kPass,
    kFail,
};

enum class ZectrixTestResult : uint8_t {
    kPass = 0,
    kFail,
    kCancelled,
    kShutdown,
};

struct ZectrixTestUpdate {
    ZectrixTestId id = ZectrixTestId::kRf;
    ZectrixTestState state = ZectrixTestState::kWait;
    char title[32] = {};
    char hint[80] = {};
    std::array<std::array<char, 80>, 4> details = {};
};

class ZectrixSelfTest {
public:
    using UpdateCallback = std::function<void(const ZectrixTestUpdate&)>;

    explicit ZectrixSelfTest(ZectrixBoard* board) : board_(board) {}

    static const char* Name(ZectrixTestId id);
    ZectrixTestResult Run(ZectrixTestId id, const UpdateCallback& callback);

private:
    ZectrixTestResult RunRf(const UpdateCallback& callback);
    ZectrixTestResult RunAudio(const UpdateCallback& callback);
    ZectrixTestResult RunRtc(const UpdateCallback& callback);
    ZectrixTestResult RunCharge(const UpdateCallback& callback);
    ZectrixTestResult RunLed(const UpdateCallback& callback);
    ZectrixTestResult RunButtons(const UpdateCallback& callback);
    ZectrixTestResult RunNfc(const UpdateCallback& callback);

    ZectrixBoard* board_ = nullptr;
};

#endif  // ZECTRIX_SELF_TEST_H_
