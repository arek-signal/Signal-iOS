//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/BaseModel.h>

NS_ASSUME_NONNULL_BEGIN

#define OWSDisappearingMessagesConfigurationDefaultExpirationDuration kDayInterval

@class SDSAnyReadTransaction;
@class TSThread;

@interface OWSDisappearingMessagesConfiguration : BaseModel

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithUniqueId:(NSString *)uniqueId NS_UNAVAILABLE;

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                 durationSeconds:(unsigned int)durationSeconds
                         enabled:(BOOL)enabled
NS_SWIFT_NAME(init(uniqueId:durationSeconds:enabled:));

// clang-format on

// --- CODE GENERATION MARKER

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) uint32_t durationSeconds;
@property (nonatomic, readonly) NSUInteger durationIndex;
@property (nonatomic, readonly) NSString *durationString;

// These methods are the only correct way to load configurations
// for a given thread; do not use anyFetchWithUniqueId.
+ (instancetype)fetchOrBuildDefaultWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction;

+ (NSArray<NSNumber *> *)validDurationsSeconds;
+ (uint32_t)maxDurationSeconds;

- (BOOL)hasChangedWithTransaction:(SDSAnyReadTransaction *)transaction;

// It's critical that we only modify copies.
// Otherwise any modifications will be made to the
// instance in the YDB object cache and hasChangedForThread:
// won't be able to detect changes.
- (instancetype)copyWithIsEnabled:(BOOL)isEnabled;
- (instancetype)copyWithDurationSeconds:(uint32_t)durationSeconds;
- (instancetype)copyAsEnabledWithDurationSeconds:(uint32_t)durationSeconds;

@end

NS_ASSUME_NONNULL_END
