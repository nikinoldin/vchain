// SPDX-License-Identifier: GPL-3.0-or-later
// Tiny check harness for the bench's unit tests (no XCTest/gtest with Command Line Tools only).
#pragma once
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace unit {
struct Counter { int total = 0, failed = 0; };
inline Counter& counter() { static Counter c; return c; }
inline std::vector<std::pair<const char*, std::function<void()>>>& registry() {
    static std::vector<std::pair<const char*, std::function<void()>>> r; return r;
}
struct Reg { Reg(const char* n, std::function<void()> f) { registry().push_back({n, std::move(f)}); } };
inline void check(bool ok, const std::string& label, const char* file, int line) {
    counter().total++;
    if (ok) printf("  %s ✓\n", label.c_str());
    else { counter().failed++; printf("  %s ✗ FAILED (%s:%d)\n", label.c_str(), file, line); }
}
inline int runAll(const char* filter) {
    for (auto& [name, fn] : registry()) {
        if (filter && std::string(name).rfind(filter, 0) != 0) continue;
        printf("-- %s\n", name); fn();
    }
    printf("%d unit checks, %d failed\n", counter().total, counter().failed);
    return counter().failed == 0 ? 0 : 1;
}
} // namespace unit

#define UNIT_CAT2(a, b) a##b
#define UNIT_CAT(a, b) UNIT_CAT2(a, b)
#define TEST(name) static void name(); static unit::Reg UNIT_CAT(reg_, name)(#name, name); static void name()
#define CHECK(cond, label) unit::check((cond), (label), __FILE__, __LINE__)
#define CHECK_NEAR(a, b, tol, label) do { double _a = (a), _b = (b); \
    unit::check(std::fabs(_a - _b) <= (tol), std::string(label) + " (" + std::to_string(_a) + " ≈ " + \
    std::to_string(_b) + " ± " + std::to_string(double(tol)) + ")", __FILE__, __LINE__); } while (0)
