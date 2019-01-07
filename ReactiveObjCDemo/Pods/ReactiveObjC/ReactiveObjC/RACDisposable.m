//
//  RACDisposable.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/16/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACDisposable.h"
#import "RACScopedDisposable.h"
#import <libkern/OSAtomic.h>

@interface RACDisposable () {
	// A copied block of type void (^)(void) containing the logic for disposal,
	// a pointer to `self` if no logic should be performed upon disposal, or
	// NULL if the receiver is already disposed.
	//
	// This should only be used atomically.
	void * volatile _disposeBlock;
}

@end

@implementation RACDisposable

#pragma mark Properties

- (BOOL)isDisposed {
	return _disposeBlock == NULL;
}

#pragma mark Lifecycle

- (instancetype)init {
	self = [super init];

    //如果没有添加block，_disposeBlock会指向自己，所以后续操作都会进行判断是否等于自己
    //_disposeBlock的类型是void *，之所以不是id类型, 避免循环引用
	_disposeBlock = (__bridge void *)self;
    
    //OSMemoryBarrier是确保前面的代码执行完了之后再执行后面的，在多核CPU中可以保证安全
	OSMemoryBarrier();

	return self;
}

- (instancetype)initWithBlock:(void (^)(void))block {
	NSCParameterAssert(block != nil);

	self = [super init];

    //这里其实不是真正的retain，只是一个桥接，把Objc类型转换为CoreFoundation类型(也就是C类型)，因为_disposeBlock是void *类型
	_disposeBlock = (void *)CFBridgingRetain([block copy]); 
	OSMemoryBarrier();

	return self;
}

+ (instancetype)disposableWithBlock:(void (^)(void))block {
	return [[self alloc] initWithBlock:block];
}

- (void)dealloc {
    //为空和等于自身都不需要额外释放或者设置NULL
	if (_disposeBlock == NULL || _disposeBlock == (__bridge void *)self) return;

	CFRelease(_disposeBlock);
	_disposeBlock = NULL;
}

#pragma mark Disposal

- (void)dispose {
	void (^disposeBlock)(void) = NULL;

	while (YES) {
		void *blockPtr = _disposeBlock;
        /*
         bool OSAtomicCompareAndSwapInt( int __oldValue, int __newValue, volatile int *__theValue );
         比较__oldValue是否与__theValue指针指向的内存位置的值是否匹配，如果匹配，则将__newValue的值存储到__theValue指向的内存位置。
         本意就是将_disposeBlock置NULL，并释放
         */
		if (OSAtomicCompareAndSwapPtrBarrier(blockPtr, NULL, &_disposeBlock)) {
            //如果不等于self，说明外面有block传进来
			if (blockPtr != (__bridge void *)self) {
                //CoreFoundation类型转换为Objc类型
				disposeBlock = CFBridgingRelease(blockPtr);
			}

			break;
		}
	}

	if (disposeBlock != nil) disposeBlock();
}

#pragma mark Scoped Disposables

- (RACScopedDisposable *)asScopedDisposable {
	return [RACScopedDisposable scopedDisposableWithDisposable:self];
}

@end
