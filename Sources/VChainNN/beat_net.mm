// SPDX-License-Identifier: GPL-3.0-or-later
#include "beat_net.h"
#import <CoreML/CoreML.h>
#import <Foundation/Foundation.h>
#include <sys/stat.h>

struct BeatNet::Impl {
    MLModel* model = nil;
    MLMultiArray* input = nil;
};

BeatNet::BeatNet() : mImpl(new Impl) {}
BeatNet::~BeatNet() = default;
bool BeatNet::ready() const { return mImpl->model != nil; }

bool BeatNet::load(const std::string& modelPath, const std::string& cacheDir, std::string* error) {
    @autoreleasepool {
        NSString* src = [NSString stringWithUTF8String:modelPath.c_str()];
        NSURL* srcURL = [NSURL fileURLWithPath:src];
        NSFileManager* fm = NSFileManager.defaultManager;
        NSURL* compiled = nil;
        if ([src.pathExtension isEqualToString:@"mlmodelc"]) {
            compiled = srcURL;
        } else {
            // Cache by name + size + mtime of the package's weights, so a new model recompiles.
            struct stat st {};
            std::string weights = modelPath + "/Data/com.apple.CoreML/weights/weight.bin";
            stat(weights.c_str(), &st);
            NSString* key = [NSString stringWithFormat:@"%@-%lld-%ld.mlmodelc", src.lastPathComponent.stringByDeletingPathExtension,
                                                       (long long)st.st_size, (long)st.st_mtime];
            NSString* dir = [NSString stringWithUTF8String:cacheDir.c_str()];
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSURL* cached = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:key]];
            if (![fm fileExistsAtPath:cached.path]) {
                NSError* err = nil;
                NSURL* tmp = [MLModel compileModelAtURL:srcURL error:&err];
                if (!tmp) { if (error) *error = err ? err.localizedDescription.UTF8String : "compile failed"; return false; }
                [fm removeItemAtURL:cached error:nil];
                if (![fm moveItemAtURL:tmp toURL:cached error:&err]) {
                    if (error) *error = err ? err.localizedDescription.UTF8String : "cache failed";
                    return false;
                }
            }
            compiled = cached;
        }
        MLModelConfiguration* cfg = [MLModelConfiguration new];
        cfg.computeUnits = MLComputeUnitsCPUAndNeuralEngine;
        NSError* err = nil;
        MLModel* m = [MLModel modelWithContentsOfURL:compiled configuration:cfg error:&err];
        if (!m) { if (error) *error = err ? err.localizedDescription.UTF8String : "load failed"; return false; }
        MLMultiArrayDataType inType = MLMultiArrayDataTypeFloat32;
        MLFeatureDescription* d = m.modelDescription.inputDescriptionsByName[@"spect"];
        if (d && d.multiArrayConstraint) inType = d.multiArrayConstraint.dataType;
        MLMultiArray* in = [[MLMultiArray alloc] initWithShape:@[@1, @(kFrames), @(kBands)] dataType:inType error:&err];
        if (!in) { if (error) *error = "input alloc failed"; return false; }
        mImpl->model = m;
        mImpl->input = in;
        return true;
    }
}

static void readOut(MLMultiArray* a, float* dst) {
    const NSInteger n = std::min<NSInteger>(a.count, BeatNet::kFrames);
    if (a.dataType == MLMultiArrayDataTypeFloat32) {
        const float* p = (const float*)a.dataPointer;
        for (NSInteger i = 0; i < n; i++) dst[i] = p[i];
    } else if (a.dataType == MLMultiArrayDataTypeFloat16) {
        const __fp16* p = (const __fp16*)a.dataPointer;
        for (NSInteger i = 0; i < n; i++) dst[i] = float(p[i]);
    } else {
        for (NSInteger i = 0; i < n; i++) dst[i] = a[i].floatValue;
    }
}

bool BeatNet::predict(const float* frames, float* beatLogits, float* downbeatLogits) {
    if (!mImpl->model) return false;
    @autoreleasepool {
        MLMultiArray* in = mImpl->input;
        const int n = kFrames * kBands;
        if (in.dataType == MLMultiArrayDataTypeFloat16) {
            __fp16* p = (__fp16*)in.dataPointer;
            for (int i = 0; i < n; i++) p[i] = (__fp16)frames[i];
        } else {
            float* p = (float*)in.dataPointer;
            for (int i = 0; i < n; i++) p[i] = frames[i];
        }
        NSError* err = nil;
        MLDictionaryFeatureProvider* fp = [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{@"spect": in} error:&err];
        if (!fp) return false;
        id<MLFeatureProvider> out = [mImpl->model predictionFromFeatures:fp error:&err];
        if (!out) return false;
        MLMultiArray* b = [out featureValueForName:@"beat"].multiArrayValue;
        MLMultiArray* d = [out featureValueForName:@"downbeat"].multiArrayValue;
        if (!b || !d) return false;
        readOut(b, beatLogits);
        readOut(d, downbeatLogits);
        return true;
    }
}
