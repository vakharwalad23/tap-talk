#ifndef OBJC_EXCEPTIONS_H
#define OBJC_EXCEPTIONS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Swift cannot catch Objective-C exceptions; AVAudioEngine raises them for graph errors it cannot report otherwise.
NSException *_Nullable tt_catch_exception(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END

#endif
