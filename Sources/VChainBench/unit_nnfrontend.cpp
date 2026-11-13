// SPDX-License-Identifier: GPL-3.0-or-later
#include "nn_front_end.h"
#include "unit.h"
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

// NNFrontEnd::stop() runs under the engine mutex (BPM module off): it must not wait for a model load, which compiles the
// model on first use (seconds). A fresh cache dir forces that compile; a restart right after must still load.
// Skipped when the model isn't on disk.
TEST(nnStopDoesNotWaitForModelLoad) {
    std::string home = getenv("HOME");
    std::string model = home + "/Music/vChainBench/models/beat_this_final0_T600_fp16.mlpackage";
    struct stat st {};
    if (stat(model.c_str(), &st) != 0) { CHECK(true, "skipped: no model at " + model); return; }
    std::string fresh = (std::filesystem::temp_directory_path() / ("vchain-nn-stop-" + std::to_string(getpid()))).string();
    NNFrontEnd nn;
    nn.start(model, fresh);
    std::this_thread::sleep_for(std::chrono::milliseconds(50)); // inside the compile
    auto t0 = std::chrono::steady_clock::now();
    nn.stop();
    double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    CHECK(ms < 20, "stop() during the load returns at once (" + std::to_string(ms) + " ms)");
    CHECK(!nn.ready(), "not ready after stop()");
    nn.start(model, home + "/Music/vChainBench/models/cache"); // waits (on its thread) for the abandoned load
    for (int i = 0; i < 800 && !nn.ready(); i++) std::this_thread::sleep_for(std::chrono::milliseconds(25));
    CHECK(nn.ready(), "restarted front end loads the model");
    nn.stop();
    nn.start(model, fresh); // the abandoned compile finished into `fresh`: loads from there
    for (int i = 0; i < 800 && !nn.ready(); i++) std::this_thread::sleep_for(std::chrono::milliseconds(25));
    CHECK(nn.ready(), "the abandoned load's cache is usable");
    nn.stop();
    std::filesystem::remove_all(fresh);
}
