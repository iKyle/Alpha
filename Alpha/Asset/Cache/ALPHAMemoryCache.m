//  ALPHACache is a modified version of TMCache
//  Modifications by Garrett Moon
//  Copyright © 2015 Pinterest. All rights reserved.

#import "ALPHAMemoryCache.h"

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
@import UIKit;
#endif

NSString * const ALPHAMemoryCachePrefix = @"com.unifiedsense.alpha.MemoryAssetCacheShared";

@interface ALPHAMemoryCache ()
#if OS_OBJECT_USE_OBJC
@property (strong, nonatomic) dispatch_queue_t concurrentQueue;
@property (strong, nonatomic) dispatch_semaphore_t lockSemaphore;
#else
@property (assign, nonatomic) dispatch_queue_t concurrentQueue;
@property (assign, nonatomic) dispatch_semaphore_t lockSemaphore;
#endif
@property (strong, nonatomic) NSMutableDictionary *dictionary;
@property (strong, nonatomic) NSMutableDictionary *dates;
@property (strong, nonatomic) NSMutableDictionary *costs;
@end

@implementation ALPHAMemoryCache

@synthesize ageLimit = _ageLimit;
@synthesize costLimit = _costLimit;
@synthesize totalCost = _totalCost;
@synthesize willAddObjectBlock = _willAddObjectBlock;
@synthesize willRemoveObjectBlock = _willRemoveObjectBlock;
@synthesize willRemoveAllObjectsBlock = _willRemoveAllObjectsBlock;
@synthesize didAddObjectBlock = _didAddObjectBlock;
@synthesize didRemoveObjectBlock = _didRemoveObjectBlock;
@synthesize didRemoveAllObjectsBlock = _didRemoveAllObjectsBlock;
@synthesize didReceiveMemoryWarningBlock = _didReceiveMemoryWarningBlock;
@synthesize didEnterBackgroundBlock = _didEnterBackgroundBlock;

#pragma mark - Initialization -

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    #if !OS_OBJECT_USE_OBJC
    dispatch_release(_concurrentQueue);
    dispatch_release(_lockSemaphore);
    _concurrentQueue = nil;
    #endif
}

- (instancetype)init
{
    if (self = [super init]) {
        _lockSemaphore = dispatch_semaphore_create(1);
        NSString *queueName = [[NSString alloc] initWithFormat:@"%@.%p", ALPHAMemoryCachePrefix, self];
        _concurrentQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_CONCURRENT);

        _dictionary = [[NSMutableDictionary alloc] init];
        _dates = [[NSMutableDictionary alloc] init];
        _costs = [[NSMutableDictionary alloc] init];

        _willAddObjectBlock = nil;
        _willRemoveObjectBlock = nil;
        _willRemoveAllObjectsBlock = nil;

        _didAddObjectBlock = nil;
        _didRemoveObjectBlock = nil;
        _didRemoveAllObjectsBlock = nil;

        _didReceiveMemoryWarningBlock = nil;
        _didEnterBackgroundBlock = nil;

        _ageLimit = 0.0;
        _costLimit = 0;
        _totalCost = 0;

        _removeAllObjectsOnMemoryWarning = YES;
        _removeAllObjectsOnEnteringBackground = YES;

        #if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
        for (NSString *name in @[UIApplicationDidReceiveMemoryWarningNotification, UIApplicationDidEnterBackgroundNotification]) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(didObserveApocalypticNotification:)
                                                         name:name
#if !defined(ALPHA_APP_EXTENSIONS)
                                                       object:[UIApplication sharedApplication]];
#else
                                                       object:nil];
#endif
        }
        #endif
    }
    return self;
}

+ (instancetype)sharedCache
{
    static id cache;
    static dispatch_once_t predicate;

    dispatch_once(&predicate, ^{
        cache = [[self alloc] init];
    });

    return cache;
}

#pragma mark - Private Methods -

- (void)didObserveApocalypticNotification:(NSNotification *)notification
{
    #if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0

    if ([[notification name] isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) {
        if (self.removeAllObjectsOnMemoryWarning)
            [self removeAllObjects:nil];

        __weak ALPHAMemoryCache *weakSelf = self;

        dispatch_async(_concurrentQueue, ^{
            ALPHAMemoryCache *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            
            [strongSelf lock];
                ALPHAMemoryCacheBlock didReceiveMemoryWarningBlock = strongSelf->_didReceiveMemoryWarningBlock;
            [strongSelf unlock];
            
            if (didReceiveMemoryWarningBlock)
                didReceiveMemoryWarningBlock(strongSelf);
        });
    } else if ([[notification name] isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
        if (self.removeAllObjectsOnEnteringBackground)
            [self removeAllObjects:nil];

        __weak ALPHAMemoryCache *weakSelf = self;

        dispatch_async(_concurrentQueue, ^{
            ALPHAMemoryCache *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf lock];
                ALPHAMemoryCacheBlock didEnterBackgroundBlock = strongSelf->_didEnterBackgroundBlock;
            [strongSelf unlock];
            
            if (didEnterBackgroundBlock)
                didEnterBackgroundBlock(strongSelf);
        });
    }
    
    #endif
}

- (void)removeObjectAndExecuteBlocksForKey:(NSString *)key
{
    [self lock];
        id object = _dictionary[key];
        NSNumber *cost = _costs[key];
        ALPHAMemoryCacheObjectBlock willRemoveObjectBlock = _willRemoveObjectBlock;
        ALPHAMemoryCacheObjectBlock didRemoveObjectBlock = _didRemoveObjectBlock;
    [self unlock];

    if (willRemoveObjectBlock)
        willRemoveObjectBlock(self, key, object);

    [self lock];
        if (cost)
            _totalCost -= [cost unsignedIntegerValue];

        [_dictionary removeObjectForKey:key];
        [_dates removeObjectForKey:key];
        [_costs removeObjectForKey:key];
    [self unlock];
    
    if (didRemoveObjectBlock)
        didRemoveObjectBlock(self, key, nil);
}

- (void)trimMemoryToDate:(NSDate *)trimDate
{
    [self lock];
        NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
        NSDictionary *dates = [_dates copy];
    [self unlock];
    
    for (NSString *key in keysSortedByDate) { // oldest objects first
        NSDate *accessDate = dates[key];
        if (!accessDate)
            continue;
        
        if ([accessDate compare:trimDate] == NSOrderedAscending) { // older than trim date
            [self removeObjectAndExecuteBlocksForKey:key];
        } else {
            break;
        }
    }
}

- (void)trimToCostLimit:(NSUInteger)limit
{
    [self lock];
        NSUInteger totalCost = _totalCost;
        NSArray *keysSortedByCost = [_costs keysSortedByValueUsingSelector:@selector(compare:)];
    [self unlock];
    
    if (totalCost <= limit) {
        return;
    }

    for (NSString *key in [keysSortedByCost reverseObjectEnumerator]) { // costliest objects first
        [self removeObjectAndExecuteBlocksForKey:key];

        [self lock];
            NSUInteger totalCost = _totalCost;
        [self unlock];
        
        if (totalCost <= limit)
            break;
    }
}

- (void)trimToCostLimitByDate:(NSUInteger)limit
{
    [self lock];
        NSUInteger totalCost = _totalCost;
        NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    [self unlock];
    
    if (totalCost <= limit)
        return;

    for (NSString *key in keysSortedByDate) { // oldest objects first
        [self removeObjectAndExecuteBlocksForKey:key];

        [self lock];
            NSUInteger totalCost = _totalCost;
        [self unlock];
        if (totalCost <= limit)
            break;
    }
}

- (void)trimToAgeLimitRecursively
{
    [self lock];
        NSTimeInterval ageLimit = _ageLimit;
    [self unlock];
    
    if (ageLimit == 0.0)
        return;

    NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:-ageLimit];
    
    [self trimMemoryToDate:date];
    
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ageLimit * NSEC_PER_SEC));
    dispatch_after(time, _concurrentQueue, ^(void){
        ALPHAMemoryCache *strongSelf = weakSelf;
        
        [strongSelf trimToAgeLimitRecursively];
    });
}

#pragma mark - Public Asynchronous Methods -

- (void)objectForKey:(NSString *)key block:(ALPHAMemoryCacheObjectBlock)block
{
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        ALPHAMemoryCache *strongSelf = weakSelf;
        id object = [strongSelf objectForKey:key];
        
        if (block)
            block(strongSelf, key, object);
    });
}

- (void)setObject:(id)object forKey:(NSString *)key block:(ALPHAMemoryCacheObjectBlock)block
{
    [self setObject:object forKey:key withCost:0 block:block];
}

- (void)setObject:(id)object forKey:(NSString *)key withCost:(NSUInteger)cost block:(ALPHAMemoryCacheObjectBlock)block
{
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        ALPHAMemoryCache *strongSelf = weakSelf;
        [strongSelf setObject:object forKey:key withCost:cost];
        
        if (block)
            block(strongSelf, key, object);
    });
}

- (void)removeObjectForKey:(NSString *)key block:(ALPHAMemoryCacheObjectBlock)block
{
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        ALPHAMemoryCache *strongSelf = weakSelf;
        [strongSelf removeObjectForKey:key];
        
        if (block)
            block(strongSelf, key, nil);
    });
}

- (void)trimToDate:(NSDate *)trimDate block:(ALPHAMemoryCacheBlock)block
{
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        ALPHAMemoryCache *strongSelf = weakSelf;
        [strongSelf trimToDate:trimDate];
        
        if (block)
            block(strongSelf);
    });
}

- (void)trimToCost:(NSUInteger)cost block:(ALPHAMemoryCacheBlock)block
{
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        ALPHAMemoryCache *strongSelf = weakSelf;
        [strongSelf trimToCost:cost];
        
        if (block)
            block(strongSelf);
    });
}

- (void)trimToCostByDate:(NSUInteger)cost block:(ALPHAMemoryCacheBlock)block
{
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        ALPHAMemoryCache *strongSelf = weakSelf;
        [strongSelf trimToCostByDate:cost];
        
        if (block)
            block(strongSelf);
    });
}

- (void)removeAllObjects:(ALPHAMemoryCacheBlock)block
{
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        ALPHAMemoryCache *strongSelf = weakSelf;
        [strongSelf removeAllObjects];
        
        if (block)
            block(strongSelf);
    });
}

- (void)enumerateObjectsWithBlock:(ALPHAMemoryCacheObjectBlock)block completionBlock:(ALPHAMemoryCacheBlock)completionBlock
{
    __weak ALPHAMemoryCache *weakSelf = self;
    
    dispatch_async(_concurrentQueue, ^{
        ALPHAMemoryCache *strongSelf = weakSelf;
        [strongSelf enumerateObjectsWithBlock:block];
        
        if (completionBlock)
            completionBlock(strongSelf);
    });
}

#pragma mark - Public Synchronous Methods -

- (id)objectForKey:(NSString *)key
{
    NSDate *now = [[NSDate alloc] init];
    
    if (!key)
        return nil;
    
    [self lock];
        id object = _dictionary[key];
    [self unlock];
        
    if (object) {
        [self lock];
            _dates[key] = now;
        [self unlock];
    }

    return object;
}

- (void)setObject:(id)object forKey:(NSString *)key
{
    [self setObject:object forKey:key withCost:0];
}

- (void)setObject:(id)object forKey:(NSString *)key withCost:(NSUInteger)cost
{
    NSDate *now = [[NSDate alloc] init];
    
    if (!key || !object)
        return;
    
    [self lock];
        ALPHAMemoryCacheObjectBlock willAddObjectBlock = _willAddObjectBlock;
        ALPHAMemoryCacheObjectBlock didAddObjectBlock = _didAddObjectBlock;
        NSUInteger costLimit = _costLimit;
    [self unlock];
    
    if (willAddObjectBlock)
        willAddObjectBlock(self, key, object);
    
    [self lock];
        _dictionary[key] = object;
        _dates[key] = now;
        _costs[key] = @(cost);
        
        _totalCost += cost;
    [self unlock];
    
    if (didAddObjectBlock)
        didAddObjectBlock(self, key, object);
    
    if (costLimit > 0)
        [self trimToCostByDate:costLimit];
}

- (void)removeObjectForKey:(NSString *)key
{
    if (!key)
        return;
    
    [self removeObjectAndExecuteBlocksForKey:key];
}

- (void)trimToDate:(NSDate *)trimDate
{
    if (!trimDate)
        return;
    
    if ([trimDate isEqualToDate:[NSDate distantPast]]) {
        [self removeAllObjects];
        return;
    }
    
    [self trimMemoryToDate:trimDate];
}

- (void)trimToCost:(NSUInteger)cost
{
    [self trimToCostLimit:cost];
}

- (void)trimToCostByDate:(NSUInteger)cost
{
    [self trimToCostLimitByDate:cost];
}

- (void)removeAllObjects
{
    [self lock];
        ALPHAMemoryCacheBlock willRemoveAllObjectsBlock = _willRemoveAllObjectsBlock;
        ALPHAMemoryCacheBlock didRemoveAllObjectsBlock = _didRemoveAllObjectsBlock;
    [self unlock];
    
    if (willRemoveAllObjectsBlock)
        willRemoveAllObjectsBlock(self);
    
    [self lock];
        [_dictionary removeAllObjects];
        [_dates removeAllObjects];
        [_costs removeAllObjects];
    
        _totalCost = 0;
    [self unlock];
    
    if (didRemoveAllObjectsBlock)
        didRemoveAllObjectsBlock(self);
    
}

- (void)enumerateObjectsWithBlock:(ALPHAMemoryCacheObjectBlock)block
{
    if (!block)
        return;
    
    [self lock];
        NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
        
        for (NSString *key in keysSortedByDate) {
            block(self, key, _dictionary[key]);
        }
    [self unlock];
}

#pragma mark - Public Thread Safe Accessors -

- (ALPHAMemoryCacheObjectBlock)willAddObjectBlock
{
    [self lock];
        ALPHAMemoryCacheObjectBlock block = _willAddObjectBlock;
    [self unlock];

    return block;
}

- (void)setWillAddObjectBlock:(ALPHAMemoryCacheObjectBlock)block
{
    [self lock];
        _willAddObjectBlock = [block copy];
    [self unlock];
}

- (ALPHAMemoryCacheObjectBlock)willRemoveObjectBlock
{
    [self lock];
        ALPHAMemoryCacheObjectBlock block = _willRemoveObjectBlock;
    [self unlock];

    return block;
}

- (void)setWillRemoveObjectBlock:(ALPHAMemoryCacheObjectBlock)block
{
    [self lock];
        _willRemoveObjectBlock = [block copy];
    [self unlock];
}

- (ALPHAMemoryCacheBlock)willRemoveAllObjectsBlock
{
    [self lock];
        ALPHAMemoryCacheBlock block = _willRemoveAllObjectsBlock;
    [self unlock];

    return block;
}

- (void)setWillRemoveAllObjectsBlock:(ALPHAMemoryCacheBlock)block
{
    [self lock];
        _willRemoveAllObjectsBlock = [block copy];
    [self unlock];
}

- (ALPHAMemoryCacheObjectBlock)didAddObjectBlock
{
    [self lock];
        ALPHAMemoryCacheObjectBlock block = _didAddObjectBlock;
    [self unlock];

    return block;
}

- (void)setDidAddObjectBlock:(ALPHAMemoryCacheObjectBlock)block
{
    [self lock];
        _didAddObjectBlock = [block copy];
    [self unlock];
}

- (ALPHAMemoryCacheObjectBlock)didRemoveObjectBlock
{
    [self lock];
        ALPHAMemoryCacheObjectBlock block = _didRemoveObjectBlock;
    [self unlock];

    return block;
}

- (void)setDidRemoveObjectBlock:(ALPHAMemoryCacheObjectBlock)block
{
    [self lock];
        _didRemoveObjectBlock = [block copy];
    [self unlock];
}

- (ALPHAMemoryCacheBlock)didRemoveAllObjectsBlock
{
    [self lock];
        ALPHAMemoryCacheBlock block = _didRemoveAllObjectsBlock;
    [self unlock];

    return block;
}

- (void)setDidRemoveAllObjectsBlock:(ALPHAMemoryCacheBlock)block
{
    [self lock];
        _didRemoveAllObjectsBlock = [block copy];
    [self unlock];
}

- (ALPHAMemoryCacheBlock)didReceiveMemoryWarningBlock
{
    [self lock];
        ALPHAMemoryCacheBlock block = _didReceiveMemoryWarningBlock;
    [self unlock];

    return block;
}

- (void)setDidReceiveMemoryWarningBlock:(ALPHAMemoryCacheBlock)block
{
    [self lock];
        _didReceiveMemoryWarningBlock = [block copy];
    [self unlock];
}

- (ALPHAMemoryCacheBlock)didEnterBackgroundBlock
{
    [self lock];
        ALPHAMemoryCacheBlock block = _didEnterBackgroundBlock;
    [self unlock];

    return block;
}

- (void)setDidEnterBackgroundBlock:(ALPHAMemoryCacheBlock)block
{
    [self lock];
        _didEnterBackgroundBlock = [block copy];
    [self unlock];
}

- (NSTimeInterval)ageLimit
{
    [self lock];
        NSTimeInterval ageLimit = _ageLimit;
    [self unlock];
    
    return ageLimit;
}

- (void)setAgeLimit:(NSTimeInterval)ageLimit
{
    [self lock];
        _ageLimit = ageLimit;
    [self unlock];
    
    [self trimToAgeLimitRecursively];
}

- (NSUInteger)costLimit
{
    [self lock];
        NSUInteger costLimit = _costLimit;
    [self unlock];

    return costLimit;
}

- (void)setCostLimit:(NSUInteger)costLimit
{
    [self lock];
        _costLimit = costLimit;
    [self unlock];

    if (costLimit > 0)
        [self trimToCostLimitByDate:costLimit];
}

- (NSUInteger)totalCost
{
    [self lock];
        NSUInteger cost = _totalCost;
    [self unlock];
    
    return cost;
}

- (void)lock
{
    dispatch_semaphore_wait(_lockSemaphore, DISPATCH_TIME_FOREVER);
}

- (void)unlock
{
    dispatch_semaphore_signal(_lockSemaphore);
}

@end
